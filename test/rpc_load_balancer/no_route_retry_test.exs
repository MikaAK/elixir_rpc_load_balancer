defmodule RpcLoadBalancer.NoRouteRetryTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  @pg_group :rpc_load_balancer

  defp start_empty_lb(name) do
    {:ok, _pid} =
      RpcLoadBalancer.start_link(
        name: name,
        selection_algorithm: SelectionAlgorithm.HashRing,
        node_match_list: ["__no_node_matches_this__"]
      )

    assert {:error, %ErrorMessage{}} = RpcLoadBalancer.get_members(name)
  end

  test "routed call retries on no-route until a member joins, then succeeds" do
    lb_name = :no_route_retry_join_lb
    start_empty_lb(lb_name)

    test_pid = self()

    caller =
      Task.async(fn ->
        RpcLoadBalancer.call(node(), Kernel, :apply, [fn -> :joined_result end, []],
          load_balancer: lb_name,
          retry_count: :infinity,
          retry_sleep: 5
        )
      end)

    # Let the routed call spin on no-route for several retry cycles before a
    # member appears, proving it did not bail immediately.
    Process.sleep(25)
    :pg.join(@pg_group, lb_name, test_pid)

    assert {:ok, :joined_result} === Task.await(caller, 2000)
  end

  test "routed call with retry?: false returns the no-members error immediately" do
    lb_name = :no_route_no_retry_lb
    start_empty_lb(lb_name)

    assert {:error, %ErrorMessage{code: :service_unavailable}} =
             RpcLoadBalancer.call(node(), Kernel, :apply, [fn -> :unreached end, []],
               load_balancer: lb_name,
               retry?: false
             )
  end

  test "routed cast retries on no-route until a member joins, then casts" do
    lb_name = :no_route_retry_cast_lb
    start_empty_lb(lb_name)

    test_pid = self()

    caller =
      Task.async(fn ->
        RpcLoadBalancer.cast(node(), Kernel, :apply, [fn -> send(test_pid, :cast_ran) end, []],
          load_balancer: lb_name,
          retry_count: :infinity,
          retry_sleep: 5
        )
      end)

    Process.sleep(25)
    :pg.join(@pg_group, lb_name, test_pid)

    assert :ok === Task.await(caller, 2000)
    assert_receive :cast_ran, 1000
  end
end
