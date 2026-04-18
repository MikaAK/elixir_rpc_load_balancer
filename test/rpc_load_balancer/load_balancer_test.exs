defmodule RpcLoadBalancer.LoadBalancerTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.Drainer
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  defp start_and_wait!(opts), do: RpcLoadBalancer.start_link(opts)

  describe "get_members/1" do
    test "returns error when no nodes are registered" do
      assert {:error, %ErrorMessage{code: :service_unavailable, message: message}} =
               RpcLoadBalancer.get_members(:missing)

      assert is_binary(message)
    end
  end

  describe "start_link/1 and select_node/1" do
    test "starts with default random algorithm" do
      {:ok, _pid} = start_and_wait!(name: :test_random_default)
      assert {:ok, _node} = RpcLoadBalancer.select_node(:test_random_default)
    end

    test "starts with round robin algorithm" do
      {:ok, _pid} =
        start_and_wait!(
          name: :test_round_robin,
          selection_algorithm: SelectionAlgorithm.RoundRobin
        )

      assert {:ok, _node} = RpcLoadBalancer.select_node(:test_round_robin)
    end

    test "starts with algorithm_opts" do
      {:ok, _pid} =
        start_and_wait!(
          name: :test_weighted,
          selection_algorithm: SelectionAlgorithm.WeightedRoundRobin,
          algorithm_opts: [weights: %{node() => 3}]
        )

      assert {:ok, _node} = RpcLoadBalancer.select_node(:test_weighted)
    end
  end

  describe "call/5 with :load_balancer" do
    test "selects a node and executes an RPC call" do
      {:ok, _pid} = start_and_wait!(name: :test_call)

      assert {:ok, :hello} ===
               RpcLoadBalancer.call(node(), Kernel, :apply, [fn -> :hello end, []],
                 load_balancer: :test_call
               )
    end

    test "executes locally when call_directly? is true" do
      {:ok, _pid} = start_and_wait!(name: :test_call_direct)

      assert {:ok, :local} ===
               RpcLoadBalancer.call(node(), Kernel, :apply, [fn -> :local end, []],
                 load_balancer: :test_call_direct,
                 call_directly?: true
               )
    end
  end

  describe "cast/5 with :load_balancer" do
    test "selects a node and executes an RPC cast" do
      {:ok, _pid} = start_and_wait!(name: :test_cast)

      assert :ok ===
               RpcLoadBalancer.cast(node(), Kernel, :apply, [fn -> :ok end, []],
                 load_balancer: :test_cast
               )
    end

    test "executes locally when call_directly? is true" do
      {:ok, _pid} = start_and_wait!(name: :test_cast_direct)

      assert :ok ===
               RpcLoadBalancer.cast(node(), Kernel, :apply, [fn -> :ok end, []],
                 load_balancer: :test_cast_direct,
                 call_directly?: true
               )
    end
  end

  describe "terminate/2" do
    test "leaves PG group on stop" do
      {:ok, _pid} = start_and_wait!(name: :test_terminate_pg)

      assert {:ok, _nodes} = RpcLoadBalancer.get_members(:test_terminate_pg)

      Supervisor.stop(:test_terminate_pg)

      assert {:error, %ErrorMessage{code: :service_unavailable}} =
               RpcLoadBalancer.get_members(:test_terminate_pg)
    end

    test "drains in-flight calls before stopping" do
      {:ok, _pid} = start_and_wait!(name: :test_terminate_drain)

      drainer_index = Drainer.register(:test_terminate_drain)
      Drainer.track_call(drainer_index)

      Task.start(fn ->
        Process.sleep(100)
        Drainer.release_call(drainer_index)
      end)

      Supervisor.stop(:test_terminate_drain)
    end
  end
end
