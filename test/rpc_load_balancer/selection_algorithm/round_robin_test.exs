defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobinTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin

  defp start_lb!(name) do
    {:ok, _pid} = RpcLoadBalancer.start_link(name: name)
    Process.sleep(100)
    name
  end

  test "cycles through nodes in order" do
    name = start_lb!(:rr_test)
    nodes = [:node_a, :node_b, :node_c]

    results = Enum.map(1..6, fn _i -> RoundRobin.choose_from_nodes(name, nodes) end)

    assert results === [:node_a, :node_b, :node_c, :node_a, :node_b, :node_c]
  end

  test "returns the only node when list has one element" do
    name = start_lb!(:rr_single)
    assert :only_node === RoundRobin.choose_from_nodes(name, [:only_node])
    assert :only_node === RoundRobin.choose_from_nodes(name, [:only_node])
  end

  test "handles concurrent access without crashing" do
    name = start_lb!(:rr_concurrent)
    nodes = [:node_a, :node_b, :node_c, :node_d]

    tasks =
      Enum.map(1..100, fn _i ->
        Task.async(fn ->
          RoundRobin.choose_from_nodes(name, nodes)
        end)
      end)

    results = Task.await_many(tasks)
    assert Enum.all?(results, &(&1 in nodes))
    assert length(results) === 100
  end
end
