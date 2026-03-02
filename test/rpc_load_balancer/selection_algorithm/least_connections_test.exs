defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastConnectionsTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastConnections


  test "selects node with fewest connections" do
    nodes = [:node_a, :node_b, :node_c]
    LeastConnections.init(:lc_test, nodes: nodes)

    assert :node_a === LeastConnections.choose_from_nodes(:lc_test, nodes)
    assert :node_b === LeastConnections.choose_from_nodes(:lc_test, nodes)
    assert :node_c === LeastConnections.choose_from_nodes(:lc_test, nodes)

    LeastConnections.release_node(:lc_test, :node_b)

    assert :node_b === LeastConnections.choose_from_nodes(:lc_test, nodes)
  end

  test "release_node decrements connection count" do
    nodes = [:node_a, :node_b]
    LeastConnections.init(:lc_release, nodes: nodes)

    _chosen = LeastConnections.choose_from_nodes(:lc_release, nodes)
    _chosen = LeastConnections.choose_from_nodes(:lc_release, nodes)

    LeastConnections.release_node(:lc_release, :node_a)

    assert :node_a === LeastConnections.choose_from_nodes(:lc_release, nodes)
  end

  test "on_node_change handles joins and leaves" do
    nodes = [:node_a]
    LeastConnections.init(:lc_change, nodes: nodes)

    :ok = LeastConnections.on_node_change(:lc_change, {:joined, [:node_b]})

    assert :node_a === LeastConnections.choose_from_nodes(:lc_change, [:node_a, :node_b])
    assert :node_b === LeastConnections.choose_from_nodes(:lc_change, [:node_a, :node_b])

    :ok = LeastConnections.on_node_change(:lc_change, {:left, [:node_a]})

    assert :node_b === LeastConnections.choose_from_nodes(:lc_change, [:node_b])
  end

  test "connection count does not go below zero" do
    nodes = [:node_a]
    LeastConnections.init(:lc_floor, nodes: nodes)

    LeastConnections.release_node(:lc_floor, :node_a)
    LeastConnections.release_node(:lc_floor, :node_a)

    assert :node_a === LeastConnections.choose_from_nodes(:lc_floor, nodes)
  end
end
