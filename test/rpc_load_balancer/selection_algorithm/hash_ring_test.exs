defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRingTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing

  test "same key always routes to the same node" do
    nodes = [:node_a, :node_b, :node_c, :node_d]

    results = Enum.map(1..10, fn _i -> HashRing.choose_from_nodes(:hr_test, nodes, key: "user:42") end)

    assert length(Enum.uniq(results)) === 1
  end

  test "different keys can route to different nodes" do
    nodes = [:node_a, :node_b, :node_c, :node_d]

    results =
      Enum.map(1..100, fn i ->
        HashRing.choose_from_nodes(:hr_test, nodes, key: "user:#{i}")
      end)

    assert length(Enum.uniq(results)) > 1
  end

  test "returns a node from the list when no key is provided" do
    nodes = [:node_a, :node_b, :node_c]
    chosen = HashRing.choose_from_nodes(:hr_no_key, nodes)
    assert chosen in nodes
  end

  test "consistent across calls with same node list and key" do
    nodes_a = [:node_c, :node_a, :node_b]
    nodes_b = [:node_b, :node_a, :node_c]

    result_a = HashRing.choose_from_nodes(:hr_order, nodes_a, key: "test_key")
    result_b = HashRing.choose_from_nodes(:hr_order, nodes_b, key: "test_key")

    assert result_a === result_b
  end
end
