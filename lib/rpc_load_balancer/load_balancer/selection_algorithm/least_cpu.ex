defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu do
  @moduledoc """
  Least CPU node selection algorithm.

  Routes calls to the node with the lowest CPU utilization. A background
  `Poller` GenServer periodically samples local and remote CPU metrics,
  storing them in `NodeCpuCache`. Selection reads directly from cache and
  randomly picks from nodes within a configurable threshold of the minimum.

  Selection never blocks on the network — if a node's cache entry is missing
  or stale, it falls back to `@default_cpu` (50.0) and lets the Poller
  refresh the value on its next tick.

  ## Usage

      RpcLoadBalancer.start_link(
        name: :my_lb,
        selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu,
        algorithm_opts: [
          poll_interval: 5_000,
          cpu_cache_ttl: 10_000,
          cpu_threshold: 5.0
        ]
      )

  ## Options

    * `:poll_interval` - Background poll frequency in ms (default: `5_000`)
    * `:cpu_cache_ttl` - Max cache age before an entry is treated as missing (default: `10_000`)
    * `:cpu_threshold` - Band width in percentage points for "close enough" selection (default: `5.0`)
    * `:cpu_sampler` - Zero-arity function returning a numeric CPU percent.
      Defaults to `:cpu_sup.util/0`. Override for tests or to plug in an
      alternative metric source.

  ## Telemetry

  The `Poller` emits `:telemetry` events under the
  `[:rpc_load_balancer, :least_cpu, :poll]` prefix. See
  `RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller` for details.
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller
  alias RpcLoadBalancer.LoadBalancer.ValueCache

  # Cache-miss default used at selection time. The Poller has its own
  # sampling-failure fallback — they're kept separate so tuning one doesn't
  # silently affect the other.
  @default_cpu 50.0
  @default_cpu_cache_ttl 10_000
  @default_cpu_threshold 5.0
  @default_poll_interval 5_000

  @impl true
  def child_specs(load_balancer_name, opts) do
    poller_opts = build_poller_opts(load_balancer_name, opts)

    [
      %{
        id: Poller.poller_name(load_balancer_name),
        start: {Poller, :start_link, [poller_opts]}
      }
    ]
  end

  defp build_poller_opts(load_balancer_name, opts) do
    base = [
      load_balancer_name: load_balancer_name,
      poll_interval: Keyword.get(opts, :poll_interval, @default_poll_interval)
    ]

    case Keyword.get(opts, :cpu_sampler) do
      nil -> base
      sampler -> Keyword.put(base, :cpu_sampler, sampler)
    end
  end

  @impl true
  def init(load_balancer_name, opts) do
    ValueCache.put({load_balancer_name, :cpu_opts}, nil, %{
      cpu_cache_ttl: Keyword.get(opts, :cpu_cache_ttl, @default_cpu_cache_ttl),
      cpu_threshold: Keyword.get(opts, :cpu_threshold, @default_cpu_threshold)
    })

    :ok
  end

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, _opts \\ []) do
    %{cpu_cache_ttl: ttl, cpu_threshold: threshold} = load_opts(load_balancer_name)
    node_cpus = measure_nodes(load_balancer_name, node_list, ttl)
    pick_from_threshold_band(node_cpus, threshold)
  end

  @impl true
  def on_node_change(_load_balancer_name, {:joined, _nodes}), do: :ok

  def on_node_change(load_balancer_name, {:left, nodes}) do
    Enum.each(nodes, fn target_node ->
      NodeCpuCache.delete({load_balancer_name, target_node})
    end)

    :ok
  end

  defp measure_nodes(load_balancer_name, node_list, ttl) do
    now = System.monotonic_time(:millisecond)

    Enum.map(node_list, fn target_node ->
      {target_node, read_node_cpu(load_balancer_name, target_node, now, ttl)}
    end)
  end

  defp read_node_cpu(load_balancer_name, target_node, now, ttl) do
    case NodeCpuCache.get({load_balancer_name, target_node}) do
      {:ok, %{cpu: cpu, fetched_at: fetched_at}} when now - fetched_at <= ttl -> cpu
      _ -> @default_cpu
    end
  end

  defp pick_from_threshold_band(node_cpus, threshold) do
    {_min_node, min_cpu} = Enum.min_by(node_cpus, &elem(&1, 1))

    node_cpus
    |> Enum.filter(fn {_node, cpu} -> cpu <= min_cpu + threshold end)
    |> Enum.random()
    |> elem(0)
  end

  defp load_opts(load_balancer_name) do
    case ValueCache.get({load_balancer_name, :cpu_opts}) do
      {:ok, %{} = opts} -> opts
      _ -> %{cpu_cache_ttl: @default_cpu_cache_ttl, cpu_threshold: @default_cpu_threshold}
    end
  end
end
