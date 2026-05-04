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
    * `:poll_startup_jitter` - Max ms of random delay before the first poll
      fires (default: `60_000`). Prevents thundering-herd multicalls when many
      nodes boot at once. Set `0` to disable.
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

  alias RpcLoadBalancer.LoadBalancer.LoadBalancerOptsCache
  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller

  # Cache-miss default used at selection time. The Poller has its own
  # sampling-failure fallback — they're kept separate so tuning one doesn't
  # silently affect the other.
  @default_cpu 50.0
  @default_cpu_cache_ttl 10_000
  @default_cpu_threshold 5.0
  @default_poll_interval 5_000

  @impl true
  def caches, do: [NodeCpuCache]

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
    [
      load_balancer_name: load_balancer_name,
      poll_interval: Keyword.get(opts, :poll_interval, @default_poll_interval)
    ]
    |> maybe_put_opt(opts, :cpu_sampler)
    |> maybe_put_opt(opts, :poll_startup_jitter)
  end

  defp maybe_put_opt(target, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> Keyword.put(target, key, value)
      :error -> target
    end
  end

  @impl true
  def init(load_balancer_name, opts) do
    LoadBalancerOptsCache.put({load_balancer_name, :cpu_opts}, nil, %{
      cpu_cache_ttl: Keyword.get(opts, :cpu_cache_ttl, @default_cpu_cache_ttl),
      cpu_threshold: Keyword.get(opts, :cpu_threshold, @default_cpu_threshold)
    })

    :ok
  end

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, _opts \\ []) do
    %{cpu_cache_ttl: ttl, cpu_threshold: threshold} = load_opts(load_balancer_name)
    now = System.monotonic_time(:millisecond)
    pick_from_threshold_band(node_list, now, ttl, threshold)
  end

  # `on_node_change` is intentionally not implemented: CPU entries are
  # node-scoped and shared across every load balancer that contains the
  # node. A single LB losing a member must NOT delete the entry — other
  # LBs may still reference the same node. Stale entries naturally age
  # out via `cpu_cache_ttl`.

  defp read_node_cpu(target_node, now, ttl) do
    case NodeCpuCache.lookup_cpu(target_node) do
      %{cpu: cpu, fetched_at: fetched_at} when now - fetched_at <= ttl -> cpu
      _ -> @default_cpu
    end
  end

  defp pick_from_threshold_band([single_node], _now, _ttl, _threshold), do: single_node

  defp pick_from_threshold_band(node_list, now, ttl, threshold) do
    node_cpus = measure_nodes(node_list, now, ttl)
    {_min_node, min_cpu} = Enum.min_by(node_cpus, &elem(&1, 1))
    upper = min_cpu + threshold

    node_cpus
    |> Enum.filter(fn {_node, cpu} -> cpu <= upper end)
    |> Enum.random()
    |> elem(0)
  end

  defp measure_nodes(node_list, now, ttl) do
    Enum.map(node_list, fn target_node ->
      {target_node, read_node_cpu(target_node, now, ttl)}
    end)
  end

  defp load_opts(load_balancer_name) do
    case LoadBalancerOptsCache.lookup({load_balancer_name, :cpu_opts}) do
      %{} = opts -> opts
      _ -> %{cpu_cache_ttl: @default_cpu_cache_ttl, cpu_threshold: @default_cpu_threshold}
    end
  end
end
