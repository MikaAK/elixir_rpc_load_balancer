defmodule RpcLoadBalancer.SelectionTelemetryTest do
  @moduledoc """
  Verify `SelectionAlgorithm.choose_from_nodes/4` emits
  `[:rpc_load_balancer, :node_selected]` events for every successful pick and
  `[:rpc_load_balancer, :node_selected, :empty]` when the algorithm returns nil.
  """

  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.Random
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin

  @selected_event [:rpc_load_balancer, :node_selected]
  @empty_event [:rpc_load_balancer, :node_selected, :empty]

  setup do
    handler_id = "selection-telemetry-#{System.unique_integer([:positive])}"
    test_pid = self()
    test_tag = make_ref()
    Process.put(:selection_test_tag, test_tag)

    :ok =
      :telemetry.attach_many(
        handler_id,
        [@selected_event, @empty_event],
        fn event, measurements, metadata, _config ->
          if Process.get(:selection_test_tag) === test_tag do
            send(test_pid, {:telemetry, event, measurements, metadata})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  describe "choose_from_nodes/4 emits :node_selected" do
    test "Random algorithm emits selected node + algorithm module + load_balancer + members_count" do
      lb_name = :"telemetry_random_#{System.unique_integer([:positive])}"
      {:ok, _pid} = RpcLoadBalancer.start_link(name: lb_name, selection_algorithm: Random)

      node = SelectionAlgorithm.choose_from_nodes(Random, lb_name, [node()], [])

      assert node === node()

      assert_receive {:telemetry, [:rpc_load_balancer, :node_selected], measurements, meta}
      assert measurements.count === 1
      assert measurements.members_count === 1
      assert meta.algorithm === Random
      assert meta.load_balancer === lb_name
      assert meta.node === node()
    end

    test "RoundRobin algorithm emits with algorithm: RoundRobin" do
      lb_name = :"telemetry_rr_#{System.unique_integer([:positive])}"

      {:ok, _pid} =
        RpcLoadBalancer.start_link(name: lb_name, selection_algorithm: RoundRobin)

      SelectionAlgorithm.choose_from_nodes(RoundRobin, lb_name, [node()], [])

      assert_receive {:telemetry, [:rpc_load_balancer, :node_selected], _measurements, meta}
      assert meta.algorithm === RoundRobin
    end

    test "members_count reflects the input list size" do
      lb_name = :"telemetry_members_#{System.unique_integer([:positive])}"
      {:ok, _pid} = RpcLoadBalancer.start_link(name: lb_name, selection_algorithm: Random)

      nodes = [node(), :"fake_a@nowhere", :"fake_b@nowhere"]
      SelectionAlgorithm.choose_from_nodes(Random, lb_name, nodes, [])

      assert_receive {:telemetry, [:rpc_load_balancer, :node_selected], measurements, _meta}
      assert measurements.members_count === 3
    end
  end

  describe "choose_from_nodes/4 emits :node_selected, :empty" do
    test "Random algorithm with empty members list fires :empty event with no :node tag" do
      lb_name = :"telemetry_empty_#{System.unique_integer([:positive])}"
      {:ok, _pid} = RpcLoadBalancer.start_link(name: lb_name, selection_algorithm: Random)

      result = SelectionAlgorithm.choose_from_nodes(Random, lb_name, [], [])

      assert is_nil(result)

      assert_receive {:telemetry, [:rpc_load_balancer, :node_selected, :empty], measurements,
                      meta}

      assert measurements.count === 1
      assert meta.algorithm === Random
      assert meta.load_balancer === lb_name
      refute Map.has_key?(meta, :node)
    end
  end
end
