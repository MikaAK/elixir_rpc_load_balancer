defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobinTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobin

  defp start_lb!(name) do
    {:ok, _pid} = RpcLoadBalancer.start_link(name: name)
    Process.sleep(100)
    name
  end

  test "distributes traffic according to weights" do
    name = start_lb!(:wrr_test)
    nodes = [:node_a, :node_b]
    WeightedRoundRobin.init(name, weights: %{node_a: 3, node_b: 1})

    results = Enum.map(1..8, fn _i -> WeightedRoundRobin.choose_from_nodes(name, nodes) end)

    node_a_count = Enum.count(results, &(&1 === :node_a))
    node_b_count = Enum.count(results, &(&1 === :node_b))

    assert node_a_count === 6
    assert node_b_count === 2
  end

  test "defaults to weight 1 for unlisted nodes" do
    name = start_lb!(:wrr_default)
    nodes = [:node_a, :node_b]
    WeightedRoundRobin.init(name, weights: %{node_a: 2})

    results = Enum.map(1..6, fn _i -> WeightedRoundRobin.choose_from_nodes(name, nodes) end)

    node_a_count = Enum.count(results, &(&1 === :node_a))
    node_b_count = Enum.count(results, &(&1 === :node_b))

    assert node_a_count === 4
    assert node_b_count === 2
  end

  test "works with empty weights map" do
    name = start_lb!(:wrr_empty)
    nodes = [:node_a, :node_b, :node_c]
    WeightedRoundRobin.init(name, weights: %{})

    results = Enum.map(1..6, fn _i -> WeightedRoundRobin.choose_from_nodes(name, nodes) end)

    assert results === [:node_a, :node_b, :node_c, :node_a, :node_b, :node_c]
  end
end
