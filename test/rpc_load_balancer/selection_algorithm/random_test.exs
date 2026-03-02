defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RandomTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.Random

  test "choose_from_nodes/3 returns a node from the list" do
    nodes = [:node_a, :node_b, :node_c]
    chosen = Random.choose_from_nodes(:test_lb, nodes)
    assert chosen in nodes
  end

  test "choose_from_nodes/3 returns the only node when list has one element" do
    assert :only_node === Random.choose_from_nodes(:test_lb, [:only_node])
  end

  test "choose_from_nodes/3 ignores opts" do
    nodes = [:node_a, :node_b]
    chosen = Random.choose_from_nodes(:test_lb, nodes, key: "some_key")
    assert chosen in nodes
  end
end
