defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRingTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing

  setup context do
    name = :"hr_#{:erlang.unique_integer([:positive])}"
    HashRing.init(name, context[:algorithm_opts] || [])
    {:ok, name: name}
  end

  test "same key always routes to the same node", %{name: name} do
    nodes = [:node_a, :node_b, :node_c, :node_d]

    results =
      Enum.map(1..10, fn _i ->
        HashRing.choose_from_nodes(name, nodes, key: "user:42")
      end)

    assert length(Enum.uniq(results)) === 1
  end

  test "different keys can route to different nodes", %{name: name} do
    nodes = [:node_a, :node_b, :node_c, :node_d]

    results =
      Enum.map(1..100, fn i ->
        HashRing.choose_from_nodes(name, nodes, key: "user:#{i}")
      end)

    assert length(Enum.uniq(results)) > 1
  end

  test "returns a node from the list when no key is provided", %{name: name} do
    nodes = [:node_a, :node_b, :node_c]
    chosen = HashRing.choose_from_nodes(name, nodes)
    assert chosen in nodes
  end

  test "consistent across calls with same node list and key", %{name: name} do
    nodes_a = [:node_c, :node_a, :node_b]
    nodes_b = [:node_b, :node_a, :node_c]

    result_a = HashRing.choose_from_nodes(name, nodes_a, key: "test_key")

    HashRing.on_node_change(name, {:joined, []})

    result_b = HashRing.choose_from_nodes(name, nodes_b, key: "test_key")

    assert result_a === result_b
  end

  describe "topology stability" do
    test "adding a node only redistributes a small fraction of keys", %{name: name} do
      original_nodes = [:node_a, :node_b, :node_c, :node_d]
      expanded_nodes = [:node_a, :node_b, :node_c, :node_d, :node_e]
      keys = Enum.map(1..1000, &"key:#{&1}")

      original_assignments =
        Enum.map(keys, fn key ->
          HashRing.choose_from_nodes(name, original_nodes, key: key)
        end)

      HashRing.on_node_change(name, {:joined, [:node_e]})

      new_assignments =
        Enum.map(keys, fn key ->
          HashRing.choose_from_nodes(name, expanded_nodes, key: key)
        end)

      changed_count =
        original_assignments
        |> Enum.zip(new_assignments)
        |> Enum.count(fn {old, new} -> old !== new end)

      max_expected_changes = div(1000, length(original_nodes))
      assert changed_count < max_expected_changes * 2
    end

    test "removing a node only redistributes keys from that node", %{name: name} do
      original_nodes = [:node_a, :node_b, :node_c, :node_d]
      reduced_nodes = [:node_a, :node_b, :node_c]
      keys = Enum.map(1..1000, &"key:#{&1}")

      original_assignments =
        Enum.map(keys, fn key ->
          HashRing.choose_from_nodes(name, original_nodes, key: key)
        end)

      HashRing.on_node_change(name, {:left, [:node_d]})

      new_assignments =
        Enum.map(keys, fn key ->
          HashRing.choose_from_nodes(name, reduced_nodes, key: key)
        end)

      keys_that_changed =
        original_assignments
        |> Enum.zip(new_assignments)
        |> Enum.filter(fn {old, new} -> old !== new end)

      Enum.each(keys_that_changed, fn {old_node, _new_node} ->
        assert old_node === :node_d
      end)
    end
  end

  describe "choose_nodes/4 (replica selection)" do
    test "returns the requested number of distinct nodes", %{name: name} do
      nodes = [:node_a, :node_b, :node_c, :node_d]

      result = HashRing.choose_nodes(name, nodes, 2, key: "user:42")

      assert length(result) === 2
      assert length(Enum.uniq(result)) === 2
      Enum.each(result, fn node -> assert node in nodes end)
    end

    test "same key always returns the same replica set", %{name: name} do
      nodes = [:node_a, :node_b, :node_c, :node_d]

      results =
        Enum.map(1..10, fn _i ->
          HashRing.choose_nodes(name, nodes, 3, key: "user:42")
        end)

      assert length(Enum.uniq(results)) === 1
    end

    test "returns all nodes when count exceeds node count", %{name: name} do
      nodes = [:node_a, :node_b, :node_c]

      result = HashRing.choose_nodes(name, nodes, 5, key: "user:42")

      assert length(result) === 3
    end

    test "first node in replica set matches single select_node", %{name: name} do
      nodes = [:node_a, :node_b, :node_c, :node_d]

      single = HashRing.choose_from_nodes(name, nodes, key: "user:99")
      [first | _rest] = HashRing.choose_nodes(name, nodes, 3, key: "user:99")

      assert first === single
    end

    test "falls back to random selection without key", %{name: name} do
      nodes = [:node_a, :node_b, :node_c, :node_d]

      result = HashRing.choose_nodes(name, nodes, 2, [])

      assert length(result) === 2
      Enum.each(result, fn node -> assert node in nodes end)
    end
  end

  describe "weight configuration" do
    @tag algorithm_opts: [weight: 64]
    test "respects custom weight", %{name: name} do
      nodes = [:node_a, :node_b, :node_c]

      results =
        Enum.map(1..100, fn i ->
          HashRing.choose_from_nodes(name, nodes, key: "user:#{i}")
        end)

      assert length(Enum.uniq(results)) > 1
    end
  end
end
