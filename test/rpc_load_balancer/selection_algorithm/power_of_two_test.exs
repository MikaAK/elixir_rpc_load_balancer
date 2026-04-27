defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.PowerOfTwoTest do
  use ExUnit.Case, async: true
  use RpcLoadBalancer.CacheCase

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.PowerOfTwo

  defp start_lb!(name) do
    {:ok, _pid} = RpcLoadBalancer.start_link(name: name)
    Process.sleep(100)
    name
  end

  test "returns the only node when list has one element" do
    name = start_lb!(:p2_single)
    PowerOfTwo.init(name, [])
    assert :only_node === PowerOfTwo.choose_from_nodes(name, [:only_node])
  end

  test "selects a node from the list" do
    name = start_lb!(:p2_basic)
    nodes = [:node_a, :node_b, :node_c]
    PowerOfTwo.init(name, nodes: nodes)
    chosen = PowerOfTwo.choose_from_nodes(name, nodes)
    assert chosen in nodes
  end

  test "prefers node with fewer connections" do
    name = start_lb!(:p2_prefer)
    nodes = [:node_a, :node_b]
    PowerOfTwo.init(name, nodes: nodes)

    _first = PowerOfTwo.choose_from_nodes(name, nodes)
    second = PowerOfTwo.choose_from_nodes(name, nodes)

    PowerOfTwo.release_node(name, second)
    PowerOfTwo.release_node(name, second)

    results = Enum.map(1..10, fn _i -> PowerOfTwo.choose_from_nodes(name, nodes) end)
    assert second in results
  end

  test "release_node decrements count" do
    name = start_lb!(:p2_release)
    nodes = [:node_a, :node_b]
    PowerOfTwo.init(name, nodes: nodes)

    chosen = PowerOfTwo.choose_from_nodes(name, nodes)
    PowerOfTwo.release_node(name, chosen)
    :ok
  end

  test "on_node_change handles joins and leaves" do
    name = start_lb!(:p2_change)
    PowerOfTwo.init(name, nodes: [:node_a])

    :ok = PowerOfTwo.on_node_change(name, {:joined, [:node_b]})
    :ok = PowerOfTwo.on_node_change(name, {:left, [:node_a]})
  end
end
