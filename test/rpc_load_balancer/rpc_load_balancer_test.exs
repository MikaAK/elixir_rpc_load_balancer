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

  test "call wraps :erpc.call/5 result" do
    assert {:ok, :ok} === RpcLoadBalancer.call(node(), Kernel, :apply, [fn -> :ok end, []])
  end

  test "cast returns :ok" do
    assert :ok === RpcLoadBalancer.cast(node(), Kernel, :apply, [fn -> :ok end, []])
  end

  describe "integration" do
    for algorithm <- @selection_algorithms do
      @algorithm algorithm
      @lb_name :"integration_#{algorithm |> Module.split() |> List.last() |> Macro.underscore()}"

      test "#{Module.split(algorithm) |> List.last()} select_node returns current node" do
        {:ok, _pid} =
          LoadBalancer.start_link(
            name: @lb_name,
            selection_algorithm: @algorithm,
            algorithm_opts: [weights: %{node() => 1}]
          )

        Process.sleep(50)

        assert {:ok, node()} === LoadBalancer.select_node(@lb_name)
      end

      test "#{Module.split(algorithm) |> List.last()} call executes on a selected node" do
        lb_name = :"integration_call_#{@algorithm |> Module.split() |> List.last() |> Macro.underscore()}"

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

      test "#{Module.split(algorithm) |> List.last()} cast executes on a selected node" do
        lb_name = :"integration_cast_#{@algorithm |> Module.split() |> List.last() |> Macro.underscore()}"

        {:ok, _pid} =
          LoadBalancer.start_link(
            name: lb_name,
            selection_algorithm: @algorithm,
            algorithm_opts: [weights: %{node() => 1}]
          )

        Process.sleep(50)

        assert :ok === LoadBalancer.cast(lb_name, Kernel, :apply, [fn -> :ok end, []])
      end

      test "#{Module.split(algorithm) |> List.last()} get_members returns current node" do
        lb_name = :"integration_members_#{@algorithm |> Module.split() |> List.last() |> Macro.underscore()}"

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
