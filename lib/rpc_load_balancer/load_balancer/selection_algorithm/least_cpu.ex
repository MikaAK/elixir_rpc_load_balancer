defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu do
  @moduledoc """
  Least CPU node selection algorithm.

  Routes calls to the node with the lowest CPU utilization. A background
  `Poller` GenServer periodically samples local and remote CPU metrics,
  storing them in `NodeCpuCache`. Selection reads from cache, refreshes
  inline if stale, and randomly picks from nodes within a configurable
  threshold of the minimum.

  ## Usage

      RpcLoadBalancer.start_link(
        name: :my_lb,
        selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu,
        algorithm_opts: [
          poll_interval: 5_000,
          cpu_cache_ttl: 10_000,
          metric_source: :scheduler_utilization,
          cpu_threshold: 5.0
        ]
      )

  ## Options

    * `:poll_interval` - Background poll frequency in ms (default: `5_000`)
    * `:cpu_cache_ttl` - Max cache age before inline refresh in ms (default: `10_000`)
    * `:metric_source` - `:scheduler_utilization` or `:cpu_sup` (default: `:scheduler_utilization`)
    * `:cpu_threshold` - Band width in percentage points for "close enough" selection (default: `5.0`)
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller
  alias RpcLoadBalancer.LoadBalancer.ValueCache

  @default_cpu 50.0
  @remote_timeout :timer.seconds(2)

  @impl true
  def child_specs(load_balancer_name, opts) do
    poller_opts = [
      load_balancer_name: load_balancer_name,
      poll_interval: Keyword.get(opts, :poll_interval, 5_000),
      metric_source: Keyword.get(opts, :metric_source, :scheduler_utilization)
    ]

    [
      %{
        id: :"#{load_balancer_name}_cpu_poller",
        start: {Poller, :start_link, [poller_opts]}
      }
    ]
  end

  @impl true
  def init(load_balancer_name, opts) do
    ValueCache.put({load_balancer_name, :cpu_opts}, nil, %{
      cpu_cache_ttl: Keyword.get(opts, :cpu_cache_ttl, 10_000),
      cpu_threshold: Keyword.get(opts, :cpu_threshold, 5.0)
    })

    :ok
  end

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, _opts \\ []) do
    %{cpu_cache_ttl: ttl, cpu_threshold: threshold} = get_opts(load_balancer_name)
    now = System.monotonic_time(:millisecond)

    node_cpus =
      Enum.map(node_list, fn target_node ->
        cpu = get_node_cpu(load_balancer_name, target_node, now, ttl)
        {target_node, cpu}
      end)

    {_min_node, min_cpu} = Enum.min_by(node_cpus, &elem(&1, 1))

    node_cpus
    |> Enum.filter(fn {_node, cpu} -> cpu <= min_cpu + threshold end)
    |> Enum.random()
    |> elem(0)
  end

  @impl true
  def on_node_change(_load_balancer_name, {:joined, _nodes}), do: :ok

  def on_node_change(load_balancer_name, {:left, nodes}) do
    Enum.each(nodes, fn target_node ->
      NodeCpuCache.delete({load_balancer_name, target_node})
    end)

    :ok
  end

  defp get_node_cpu(load_balancer_name, target_node, now, ttl) do
    case NodeCpuCache.get({load_balancer_name, target_node}) do
      {:ok, %{cpu: cpu, fetched_at: fetched_at}} when now - fetched_at <= ttl ->
        cpu

      _ ->
        refresh_node_cpu(load_balancer_name, target_node, now)
    end
  end

  defp refresh_node_cpu(load_balancer_name, target_node, now) do
    case fetch_remote_cpu(load_balancer_name, target_node) do
      {:ok, %{cpu: cpu}} ->
        NodeCpuCache.put(
          {load_balancer_name, target_node},
          nil,
          %{cpu: cpu, fetched_at: now}
        )

        cpu

      _ ->
        @default_cpu
    end
  end

  defp fetch_remote_cpu(load_balancer_name, target_node) do
    :erpc.call(
      target_node,
      NodeCpuCache,
      :get,
      [{load_balancer_name, target_node}],
      @remote_timeout
    )
  catch
    _, _ -> :error
  end

  defp get_opts(load_balancer_name) do
    case ValueCache.get({load_balancer_name, :cpu_opts}) do
      {:ok, %{} = opts} -> opts
      _ -> %{cpu_cache_ttl: 10_000, cpu_threshold: 5.0}
    end
  end
end
