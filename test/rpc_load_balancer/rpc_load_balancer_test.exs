defmodule RpcLoadBalancerTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer
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
          LoadBalancer.start_link(
            name: @lb_name,
            selection_algorithm: @algorithm,
            algorithm_opts: [weights: %{node() => 1}]
          )

        Process.sleep(50)

        assert {:ok, node()} === LoadBalancer.select_node(@lb_name)
      end

      test "#{short_name} call executes on a selected node" do
        lb_name = :"integration_call_#{algorithm_short_name(@algorithm)}"

        {:ok, _pid} =
          LoadBalancer.start_link(
            name: lb_name,
            selection_algorithm: @algorithm,
            algorithm_opts: [weights: %{node() => 1}]
          )

        Process.sleep(50)

        assert {:ok, :integration_result} ===
                 LoadBalancer.call(lb_name, Kernel, :apply, [fn -> :integration_result end, []])
      end

      test "#{short_name} cast executes on a selected node" do
        lb_name = :"integration_cast_#{algorithm_short_name(@algorithm)}"

        {:ok, _pid} =
          LoadBalancer.start_link(
            name: lb_name,
            selection_algorithm: @algorithm,
            algorithm_opts: [weights: %{node() => 1}]
          )

        Process.sleep(50)

        assert :ok === LoadBalancer.cast(lb_name, Kernel, :apply, [fn -> :ok end, []])
      end

      test "#{short_name} get_members returns current node" do
        lb_name = :"integration_members_#{algorithm_short_name(@algorithm)}"

        {:ok, _pid} =
          LoadBalancer.start_link(
            name: lb_name,
            selection_algorithm: @algorithm,
            algorithm_opts: [weights: %{node() => 1}]
          )

        Process.sleep(50)

        assert {:ok, [node()]} === LoadBalancer.get_members(lb_name)
      end
    end
  end
end
