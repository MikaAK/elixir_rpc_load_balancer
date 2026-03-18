defmodule RpcLoadBalancerTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  @selection_algorithms [
    SelectionAlgorithm.Random,
    SelectionAlgorithm.RoundRobin,
    SelectionAlgorithm.LeastConnections,
    SelectionAlgorithm.PowerOfTwo,
    SelectionAlgorithm.HashRing,
    SelectionAlgorithm.WeightedRoundRobin
  ]

  defp algorithm_short_name(algorithm) do
    algorithm
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  test "call wraps :erpc.call/5 result" do
    assert {:ok, :ok} === RpcLoadBalancer.call(node(), Kernel, :apply, [fn -> :ok end, []])
  end

  test "cast returns :ok" do
    assert :ok === RpcLoadBalancer.cast(node(), Kernel, :apply, [fn -> :ok end, []])
  end

  describe "integration" do
    for algorithm <- @selection_algorithms do
      short_name = List.last(Module.split(algorithm))
      snake_name = Macro.underscore(short_name)

      @algorithm algorithm
      @lb_name :"integration_#{snake_name}"

      test "#{short_name} select_node returns current node" do
        {:ok, _pid} =
          RpcLoadBalancer.start_link(
            name: @lb_name,
            selection_algorithm: @algorithm,
            algorithm_opts: [weights: %{node() => 1}]
          )

        Process.sleep(100)

        assert {:ok, node()} === RpcLoadBalancer.select_node(@lb_name)
      end

      test "#{short_name} call executes on a selected node" do
        lb_name = :"integration_call_#{algorithm_short_name(@algorithm)}"

        {:ok, _pid} =
          RpcLoadBalancer.start_link(
            name: lb_name,
            selection_algorithm: @algorithm,
            algorithm_opts: [weights: %{node() => 1}]
          )

        Process.sleep(100)

        assert {:ok, :integration_result} ===
                 RpcLoadBalancer.lb_call(lb_name, Kernel, :apply, [fn -> :integration_result end, []])
      end

      test "#{short_name} cast executes on a selected node" do
        lb_name = :"integration_cast_#{algorithm_short_name(@algorithm)}"

        {:ok, _pid} =
          RpcLoadBalancer.start_link(
            name: lb_name,
            selection_algorithm: @algorithm,
            algorithm_opts: [weights: %{node() => 1}]
          )

        Process.sleep(100)

        assert :ok === RpcLoadBalancer.lb_cast(lb_name, Kernel, :apply, [fn -> :ok end, []])
      end

      test "#{short_name} get_members returns current node" do
        lb_name = :"integration_members_#{algorithm_short_name(@algorithm)}"

        {:ok, _pid} =
          RpcLoadBalancer.start_link(
            name: lb_name,
            selection_algorithm: @algorithm,
            algorithm_opts: [weights: %{node() => 1}]
          )

        Process.sleep(100)

        assert {:ok, [node()]} === RpcLoadBalancer.get_members(lb_name)
      end
    end

    test "module CallDirect call executes locally without erpc" do
      {:ok, _pid} =
        RpcLoadBalancer.start_link(
          name: :integration_call_direct_call,
          selection_algorithm: SelectionAlgorithm.CallDirect
        )

      Process.sleep(100)

      assert {:ok, :direct_result} ===
               RpcLoadBalancer.lb_call(
                 :integration_call_direct_call,
                 Kernel,
                 :apply,
                 [fn -> :direct_result end, []]
               )
    end

    test "module CallDirect cast executes locally without erpc" do
      test_pid = self()

      {:ok, _pid} =
        RpcLoadBalancer.start_link(
          name: :integration_call_direct_cast,
          selection_algorithm: SelectionAlgorithm.CallDirect
        )

      Process.sleep(100)

      assert :ok ===
               RpcLoadBalancer.lb_cast(
                 :integration_call_direct_cast,
                 Kernel,
                 :apply,
                 [fn -> send(test_pid, :cast_executed) end, []]
               )

      assert_receive :cast_executed, 1000
    end
  end
end
