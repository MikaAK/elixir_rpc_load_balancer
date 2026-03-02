defmodule RpcLoadBalancerTest do
  use ExUnit.Case, async: true

  test "call wraps :erpc.call/5 result" do
    assert {:ok, :ok} === RpcLoadBalancer.call(node(), Kernel, :apply, [fn -> :ok end, []])
  end

  test "cast returns :ok" do
    assert :ok === RpcLoadBalancer.cast(node(), Kernel, :apply, [fn -> :ok end, []])
  end
end
