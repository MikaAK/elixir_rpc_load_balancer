defmodule RpcLoadBalancer.LoadBalancerTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  defp start_and_wait!(opts) do
    {:ok, pid} = LoadBalancer.start_link(opts)
    Process.sleep(50)
    {:ok, pid}
  end

  describe "get_members/1" do
    test "returns error when no nodes are registered" do
      assert {:error, %ErrorMessage{code: :service_unavailable, message: message}} =
               LoadBalancer.get_members(:missing)

      assert is_binary(message)
    end
  end

  describe "start_link/1 and select_node/1" do
    test "starts with default random algorithm" do
      {:ok, _pid} = start_and_wait!(name: :test_random_default)
      assert {:ok, _node} = LoadBalancer.select_node(:test_random_default)
    end

    test "starts with round robin algorithm" do
      {:ok, _pid} =
        start_and_wait!(
          name: :test_round_robin,
          selection_algorithm: SelectionAlgorithm.RoundRobin
        )

      assert {:ok, _node} = LoadBalancer.select_node(:test_round_robin)
    end

    test "starts with algorithm_opts" do
      {:ok, _pid} =
        start_and_wait!(
          name: :test_weighted,
          selection_algorithm: SelectionAlgorithm.WeightedRoundRobin,
          algorithm_opts: [weights: %{node() => 3}]
        )

      assert {:ok, _node} = LoadBalancer.select_node(:test_weighted)
    end
  end

  describe "convenience call/5" do
    test "selects a node and executes an RPC call" do
      {:ok, _pid} = start_and_wait!(name: :test_call)

      assert {:ok, :hello} ===
               LoadBalancer.call(:test_call, Kernel, :apply, [fn -> :hello end, []])
    end
  end

  describe "convenience cast/5" do
    test "selects a node and executes an RPC cast" do
      {:ok, _pid} = start_and_wait!(name: :test_cast)

      assert :ok === LoadBalancer.cast(:test_cast, Kernel, :apply, [fn -> :ok end, []])
    end
  end
end
