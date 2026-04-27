defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpuTest do
  use ExUnit.Case, async: true
  use RpcLoadBalancer.CacheCase

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller
  alias RpcLoadBalancer.LoadBalancer.ValueCache

  defp start_lb!(name, opts \\ []) do
    default_opts = [
      name: name,
      selection_algorithm: LeastCpu,
      algorithm_opts: Keyword.merge([poll_interval: 60_000, poll_startup_jitter: 0], opts)
    ]

    start_supervised!({RpcLoadBalancer, default_opts}, id: name)
    await_algorithm_init!(name)
    name
  end

  defp poll_until(fun, attempts \\ 40, sleep_ms \\ 25) do
    case fun.() do
      nil when attempts > 0 ->
        Process.sleep(sleep_ms)
        poll_until(fun, attempts - 1, sleep_ms)

      nil ->
        nil

      value ->
        value
    end
  end

  defp await_algorithm_init!(name) do
    opts =
      poll_until(fn ->
        case ValueCache.get({name, :cpu_opts}) do
          {:ok, %{} = opts} -> opts
          _ -> nil
        end
      end)

    opts || flunk("LeastCpu.init/2 did not populate ValueCache for #{inspect(name)}")
  end

  defp seed_cpu!(name, metrics) do
    now = System.monotonic_time(:millisecond)

    Enum.each(metrics, fn {node_name, cpu} ->
      NodeCpuCache.put_cpu(name, node_name, %{cpu: cpu, fetched_at: now})
    end)
  end

  test "selects node with lowest CPU" do
    name = start_lb!(:lcpu_basic)
    nodes = [:node_a, :node_b, :node_c]
    seed_cpu!(name, node_a: 80.0, node_b: 20.0, node_c: 50.0)

    assert LeastCpu.choose_from_nodes(name, nodes) === :node_b
  end

  test "cpu_threshold option drives the close-enough band" do
    name = start_lb!(:lcpu_threshold, cpu_threshold: 2.0)
    nodes = [:node_a, :node_b, :node_c]
    seed_cpu!(name, node_a: 22.0, node_b: 23.5, node_c: 25.0)

    results = for _ <- 1..200, do: LeastCpu.choose_from_nodes(name, nodes)
    unique = Enum.uniq(results)

    assert :node_a in unique
    assert :node_b in unique
    refute :node_c in unique
  end

  test "tight threshold keeps selection on the minimum only" do
    name = start_lb!(:lcpu_tight, cpu_threshold: 0.5)
    nodes = [:node_a, :node_b]
    seed_cpu!(name, node_a: 20.0, node_b: 22.0)

    results = for _ <- 1..50, do: LeastCpu.choose_from_nodes(name, nodes)
    assert Enum.uniq(results) === [:node_a]
  end

  test "uses midpoint default (50.0) for nodes without cached CPU" do
    name = start_lb!(:lcpu_missing)
    nodes = [:node_a, :node_b]
    seed_cpu!(name, node_a: 60.0)

    assert LeastCpu.choose_from_nodes(name, nodes) === :node_b
  end

  test "on_node_change :left removes departed node metrics" do
    name = start_lb!(:lcpu_leave)
    seed_cpu!(name, node_a: 30.0, node_b: 40.0)

    :ok = LeastCpu.on_node_change(name, {:left, [:node_a]})

    assert NodeCpuCache.get_cpu(name, :node_a) === {:ok, nil}
    assert {:ok, %{cpu: 40.0}} = NodeCpuCache.get_cpu(name, :node_b)
  end

  test "on_node_change :joined is a no-op and leaves cache untouched" do
    name = start_lb!(:lcpu_join)
    seed_cpu!(name, node_a: 10.0)

    assert LeastCpu.on_node_change(name, {:joined, [:node_x]}) === :ok
    assert {:ok, %{cpu: 10.0}} = NodeCpuCache.get_cpu(name, :node_a)
    assert NodeCpuCache.get_cpu(name, :node_x) === {:ok, nil}
  end

  test "caches/0 declares NodeCpuCache so the application boots it once" do
    assert LeastCpu.caches() === [NodeCpuCache]
  end

  test "child_specs returns only the Poller spec — caches are application-owned" do
    specs = LeastCpu.child_specs(:test_lb, poll_interval: 5_000)

    assert [poller_spec] = specs
    assert %{id: :test_lb_cpu_poller, start: {_, :start_link, [poller_opts]}} = poller_spec
    assert Keyword.fetch!(poller_opts, :load_balancer_name) === :test_lb
    assert Keyword.fetch!(poller_opts, :poll_interval) === 5_000
  end

  test "child_specs forwards cpu_sampler when provided" do
    sampler = fn -> 42 end
    specs = LeastCpu.child_specs(:test_lb_sampler, cpu_sampler: sampler)

    assert [%{start: {_, :start_link, [poller_opts]}}] = specs
    assert Keyword.fetch!(poller_opts, :cpu_sampler) === sampler
  end

  test "child_specs omits cpu_sampler when not provided" do
    specs = LeastCpu.child_specs(:test_lb_nosampler, [])

    assert [%{start: {_, :start_link, [poller_opts]}}] = specs
    refute Keyword.has_key?(poller_opts, :cpu_sampler)
  end

  test "child_specs forwards poll_startup_jitter when provided" do
    specs = LeastCpu.child_specs(:test_lb_jitter, poll_startup_jitter: 1_000)

    assert [%{start: {_, :start_link, [poller_opts]}}] = specs
    assert Keyword.fetch!(poller_opts, :poll_startup_jitter) === 1_000
  end

  test "child_specs omits poll_startup_jitter when not provided" do
    specs = LeastCpu.child_specs(:test_lb_no_jitter, [])

    assert [%{start: {_, :start_link, [poller_opts]}}] = specs
    refute Keyword.has_key?(poller_opts, :poll_startup_jitter)
  end

  test "stale cache entry is treated as missing and does not trigger inline refresh" do
    name = start_lb!(:lcpu_stale, poll_interval: 60_000, cpu_cache_ttl: 60_000)
    nodes = [:node_a, :node_b]
    now = System.monotonic_time(:millisecond)

    stale_entry = %{cpu: 20.0, fetched_at: now - 120_000}
    fresh_entry = %{cpu: 30.0, fetched_at: now}
    NodeCpuCache.put_cpu(name, :node_a, stale_entry)
    NodeCpuCache.put_cpu(name, :node_b, fresh_entry)

    assert LeastCpu.choose_from_nodes(name, nodes) === :node_b

    assert {:ok, ^stale_entry} = NodeCpuCache.get_cpu(name, :node_a)
    assert {:ok, ^fresh_entry} = NodeCpuCache.get_cpu(name, :node_b)
  end

  test "algorithm_opts flow through init/2 into ValueCache" do
    name = start_lb!(:lcpu_opts_flow, cpu_threshold: 7.5, cpu_cache_ttl: 20_000)

    assert {:ok, %{cpu_threshold: 7.5, cpu_cache_ttl: 20_000}} =
             ValueCache.get({name, :cpu_opts})
  end

  test "poller is registered before the LoadBalancer GenServer finishes booting" do
    name =
      start_lb!(:lcpu_ordering,
        poll_interval: 50,
        cpu_sampler: fn -> 17 end
      )

    # `start_lb!` returns only after every child's `start_link` has completed,
    # so the Poller must be registered by this point — demonstrating the
    # algorithm_children-before-LoadBalancer ordering in the supervisor.
    poller_pid = Process.whereis(Poller.poller_name(name))
    assert is_pid(poller_pid)
    assert Process.alive?(poller_pid)

    entry =
      poll_until(fn ->
        case NodeCpuCache.get_cpu(name, node()) do
          {:ok, %{cpu: 17.0} = map} -> map
          _ -> nil
        end
      end)

    assert entry, "poller did not write the injected CPU value within the timeout"

    assert LeastCpu.choose_from_nodes(name, [node()]) === node()
  end
end
