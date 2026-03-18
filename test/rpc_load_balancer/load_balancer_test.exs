defmodule RpcLoadBalancer.LoadBalancerTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.Drainer
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  defp start_and_wait!(opts) do
    {:ok, pid} = RpcLoadBalancer.start_link(opts)
    Process.sleep(100)
    {:ok, pid}
  end

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

  describe "lb_call/5" do
    test "selects a node and executes an RPC call" do
      {:ok, _pid} = start_and_wait!(name: :test_call)

      assert {:ok, :hello} ===
               RpcLoadBalancer.lb_call(:test_call, Kernel, :apply, [fn -> :hello end, []])
    end

    test "executes locally when call_directly? is true" do
      {:ok, _pid} = start_and_wait!(name: :test_call_direct)

      assert {:ok, :local} ===
               RpcLoadBalancer.lb_call(:test_call_direct, Kernel, :apply, [fn -> :local end, []],
                 call_directly?: true
               )
    end
  end

  describe "lb_cast/5" do
    test "selects a node and executes an RPC cast" do
      {:ok, _pid} = start_and_wait!(name: :test_cast)

      assert :ok === RpcLoadBalancer.lb_cast(:test_cast, Kernel, :apply, [fn -> :ok end, []])
    end

    test "executes locally when call_directly? is true" do
      {:ok, _pid} = start_and_wait!(name: :test_cast_direct)

      assert :ok ===
               RpcLoadBalancer.lb_cast(:test_cast_direct, Kernel, :apply, [fn -> :ok end, []],
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

      Drainer.track_call(:test_terminate_drain)

      Task.start(fn ->
        Process.sleep(100)
        Drainer.release_call(:test_terminate_drain)
      end)

      Supervisor.stop(:test_terminate_drain)
    end
  end
end
