defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastConnectionsTest do
  use ExUnit.Case, async: true
  use RpcLoadBalancer.CacheCase

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastConnections

  defp start_lb!(name) do
    {:ok, _pid} = RpcLoadBalancer.start_link(name: name)
    Process.sleep(100)
    name
  end

  test "selects node with fewest connections" do
    name = start_lb!(:lc_test)
    nodes = [:node_a, :node_b, :node_c]
    LeastConnections.init(name, nodes: nodes)

    assert :node_a === LeastConnections.choose_from_nodes(:lc_test, nodes)
    assert :node_b === LeastConnections.choose_from_nodes(:lc_test, nodes)
    assert :node_c === LeastConnections.choose_from_nodes(:lc_test, nodes)

    LeastConnections.release_node(:lc_test, :node_b)

    assert :node_b === LeastConnections.choose_from_nodes(:lc_test, nodes)
  end

  test "release_node decrements connection count" do
    name = start_lb!(:lc_release)
    nodes = [:node_a, :node_b]
    LeastConnections.init(name, nodes: nodes)

    _chosen = LeastConnections.choose_from_nodes(name, nodes)
    _chosen = LeastConnections.choose_from_nodes(name, nodes)

    LeastConnections.release_node(name, :node_a)

    assert :node_a === LeastConnections.choose_from_nodes(name, nodes)
  end

  test "on_node_change handles joins and leaves" do
    name = start_lb!(:lc_change)
    nodes = [:node_a]
    LeastConnections.init(name, nodes: nodes)

    :ok = LeastConnections.on_node_change(name, {:joined, [:node_b]})

    assert :node_a === LeastConnections.choose_from_nodes(name, [:node_a, :node_b])
    assert :node_b === LeastConnections.choose_from_nodes(name, [:node_a, :node_b])

    :ok = LeastConnections.on_node_change(name, {:left, [:node_a]})

    assert :node_b === LeastConnections.choose_from_nodes(name, [:node_b])
  end

  test "connection count does not go below zero" do
    name = start_lb!(:lc_floor)
    nodes = [:node_a]
    LeastConnections.init(name, nodes: nodes)

    LeastConnections.release_node(name, :node_a)
    LeastConnections.release_node(name, :node_a)

    assert :node_a === LeastConnections.choose_from_nodes(name, nodes)
  end
end
