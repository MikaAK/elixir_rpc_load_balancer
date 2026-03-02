defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobinTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin


  test "cycles through nodes in order" do
    nodes = [:node_a, :node_b, :node_c]

    results = Enum.map(1..6, fn _i -> RoundRobin.choose_from_nodes(:rr_test, nodes) end)

    assert results === [:node_a, :node_b, :node_c, :node_a, :node_b, :node_c]
  end

  test "returns the only node when list has one element" do
    assert :only_node === RoundRobin.choose_from_nodes(:rr_single, [:only_node])
    assert :only_node === RoundRobin.choose_from_nodes(:rr_single, [:only_node])
  end

  test "handles concurrent access without crashing" do
    nodes = [:node_a, :node_b, :node_c, :node_d]

    tasks =
      Enum.map(1..100, fn _i ->
        Task.async(fn ->
          RoundRobin.choose_from_nodes(:rr_concurrent, nodes)
        end)
      end)

    results = Task.await_many(tasks)
    assert Enum.all?(results, &(&1 in nodes))
    assert length(results) === 100
  end
end
