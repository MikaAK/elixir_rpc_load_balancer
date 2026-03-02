defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.PowerOfTwoTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.PowerOfTwo


  test "returns the only node when list has one element" do
    PowerOfTwo.init(:p2_single, [])
    assert :only_node === PowerOfTwo.choose_from_nodes(:p2_single, [:only_node])
  end

  test "selects a node from the list" do
    nodes = [:node_a, :node_b, :node_c]
    PowerOfTwo.init(:p2_basic, nodes: nodes)
    chosen = PowerOfTwo.choose_from_nodes(:p2_basic, nodes)
    assert chosen in nodes
  end

  test "prefers node with fewer connections" do
    nodes = [:node_a, :node_b]
    PowerOfTwo.init(:p2_prefer, nodes: nodes)

    _first = PowerOfTwo.choose_from_nodes(:p2_prefer, nodes)
    second = PowerOfTwo.choose_from_nodes(:p2_prefer, nodes)

    PowerOfTwo.release_node(:p2_prefer, second)
    PowerOfTwo.release_node(:p2_prefer, second)

    results = Enum.map(1..10, fn _i -> PowerOfTwo.choose_from_nodes(:p2_prefer, nodes) end)
    assert second in results
  end

  test "release_node decrements count" do
    nodes = [:node_a, :node_b]
    PowerOfTwo.init(:p2_release, nodes: nodes)

    chosen = PowerOfTwo.choose_from_nodes(:p2_release, nodes)
    PowerOfTwo.release_node(:p2_release, chosen)
    :ok
  end

  test "on_node_change handles joins and leaves" do
    PowerOfTwo.init(:p2_change, nodes: [:node_a])

    :ok = PowerOfTwo.on_node_change(:p2_change, {:joined, [:node_b]})
    :ok = PowerOfTwo.on_node_change(:p2_change, {:left, [:node_a]})
  end
end
