defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobinTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobin


  test "distributes traffic according to weights" do
    nodes = [:node_a, :node_b]
    WeightedRoundRobin.init(:wrr_test, weights: %{node_a: 3, node_b: 1})

    results = Enum.map(1..8, fn _i -> WeightedRoundRobin.choose_from_nodes(:wrr_test, nodes) end)

    node_a_count = Enum.count(results, &(&1 === :node_a))
    node_b_count = Enum.count(results, &(&1 === :node_b))

    assert node_a_count === 6
    assert node_b_count === 2
  end

  test "defaults to weight 1 for unlisted nodes" do
    nodes = [:node_a, :node_b]
    WeightedRoundRobin.init(:wrr_default, weights: %{node_a: 2})

    results = Enum.map(1..6, fn _i -> WeightedRoundRobin.choose_from_nodes(:wrr_default, nodes) end)

    node_a_count = Enum.count(results, &(&1 === :node_a))
    node_b_count = Enum.count(results, &(&1 === :node_b))

    assert node_a_count === 4
    assert node_b_count === 2
  end

  test "works with empty weights map" do
    nodes = [:node_a, :node_b, :node_c]
    WeightedRoundRobin.init(:wrr_empty, weights: %{})

    results = Enum.map(1..6, fn _i -> WeightedRoundRobin.choose_from_nodes(:wrr_empty, nodes) end)

    assert results === [:node_a, :node_b, :node_c, :node_a, :node_b, :node_c]
  end
end
