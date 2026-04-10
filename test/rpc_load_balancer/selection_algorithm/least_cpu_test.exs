defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpuTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu

  defp start_lb!(name, opts \\ []) do
    default_opts = [
      name: name,
      selection_algorithm: LeastCpu,
      algorithm_opts: Keyword.merge([poll_interval: 60_000], opts)
    ]

    {:ok, _pid} = RpcLoadBalancer.start_link(default_opts)
    Process.sleep(100)
    name
  end

  defp seed_cpu!(name, metrics) do
    now = System.monotonic_time(:millisecond)

    Enum.each(metrics, fn {node_name, cpu} ->
      NodeCpuCache.put({name, node_name}, nil, %{cpu: cpu, fetched_at: now})
    end)
  end

  test "selects node with lowest CPU" do
    name = start_lb!(:lcpu_basic)
    nodes = [:node_a, :node_b, :node_c]
    seed_cpu!(name, node_a: 80.0, node_b: 20.0, node_c: 50.0)

    assert :node_b === LeastCpu.choose_from_nodes(name, nodes)
  end

  test "randomly selects among nodes within threshold" do
    name = start_lb!(:lcpu_threshold, cpu_threshold: 5.0)
    nodes = [:node_a, :node_b, :node_c]
    seed_cpu!(name, node_a: 22.0, node_b: 25.0, node_c: 50.0)

    results = Enum.map(1..100, fn _ -> LeastCpu.choose_from_nodes(name, nodes) end)
    unique = Enum.uniq(results)

    assert :node_a in unique
    assert :node_b in unique
    refute :node_c in unique
  end

  test "uses midpoint default (50.0) for nodes without cached CPU" do
    name = start_lb!(:lcpu_missing)
    nodes = [:node_a, :node_b]
    seed_cpu!(name, node_a: 60.0)

    assert :node_b === LeastCpu.choose_from_nodes(name, nodes)
  end

  test "on_node_change :left removes departed node metrics" do
    name = start_lb!(:lcpu_leave)
    seed_cpu!(name, node_a: 30.0, node_b: 40.0)

    :ok = LeastCpu.on_node_change(name, {:left, [:node_a]})

    assert {:ok, nil} === NodeCpuCache.get({name, :node_a})
    assert {:ok, %{cpu: 40.0}} = NodeCpuCache.get({name, :node_b})
  end

  test "on_node_change :joined is a no-op" do
    name = start_lb!(:lcpu_join)
    assert :ok === LeastCpu.on_node_change(name, {:joined, [:node_x]})
  end

  test "child_specs returns poller child spec" do
    specs = LeastCpu.child_specs(:test_lb, poll_interval: 5_000, metric_source: :scheduler_utilization)
    assert length(specs) === 1
    assert [%{id: _id, start: {LeastCpu.Poller, :start_link, [_opts]}}] = specs
  end

  test "poller writes local CPU and algorithm reads it" do
    name = start_lb!(:lcpu_integration, poll_interval: 100)
    Process.sleep(200)

    {:ok, %{cpu: cpu}} = NodeCpuCache.get({name, node()})
    assert is_float(cpu)
    assert cpu >= 0.0 and cpu <= 100.0

    nodes = [node()]
    assert node() === LeastCpu.choose_from_nodes(name, nodes)
  end

  test "stale cache entry triggers inline refresh and falls back to midpoint default" do
    name = start_lb!(:lcpu_stale, poll_interval: 60_000, cpu_cache_ttl: 1)
    nodes = [:node_a, :node_b]
    now = System.monotonic_time(:millisecond)

    # node_a's entry is stale (5s old, ttl is 1ms), inline refresh will fail
    # (fake node), so node_a gets 50.0 midpoint default.
    # node_b has fresh data at 30.0, so node_b should be selected.
    NodeCpuCache.put({name, :node_a}, nil, %{cpu: 20.0, fetched_at: now - 5_000})
    NodeCpuCache.put({name, :node_b}, nil, %{cpu: 30.0, fetched_at: now})

    selected = LeastCpu.choose_from_nodes(name, nodes)
    assert selected === :node_b
  end
end
