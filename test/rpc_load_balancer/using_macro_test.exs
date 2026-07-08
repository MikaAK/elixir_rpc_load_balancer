defmodule RpcLoadBalancer.UsingMacroTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  defmodule TestLB do
    use RpcLoadBalancer, selection_algorithm: SelectionAlgorithm.CallDirect
  end

  setup do
    start_supervised!(TestLB)
    :ok
  end

  test "child_spec/1 uses the module name as the id" do
    assert %{id: TestLB, start: {TestLB, :start_link, [[]]}} = TestLB.child_spec([])
  end

  test "starts a load balancer registered under the module name" do
    assert {:ok, [node()]} === TestLB.get_members()
  end

  test "select_node/1 delegates with the module as the load balancer name" do
    assert {:ok, node()} === TestLB.select_node()
  end

  test "call/5 routes through the module's load balancer" do
    assert {:ok, :called} === TestLB.call(node(), Kernel, :apply, [fn -> :called end, []])
  end

  test "cast/5 routes through the module's load balancer" do
    test_pid = self()
    assert :ok === TestLB.cast(node(), Kernel, :apply, [fn -> send(test_pid, :casted) end, []])
    assert_receive :casted, 1000
  end

  test "call_on_random_node/5 delegates through the module's load balancer" do
    assert {:ok, :random} === TestLB.call_on_random_node("", Kernel, :apply, [fn -> :random end, []])
  end

  test "cast_on_random_node/5 delegates through the module's load balancer" do
    test_pid = self()

    assert :ok ===
             TestLB.cast_on_random_node("", Kernel, :apply, [fn -> send(test_pid, :cast_random) end, []])

    assert_receive :cast_random, 1000
  end
end
