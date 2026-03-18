defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirectTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirect

  test "local?/0 returns true" do
    assert CallDirect.local?()
  end

  test "choose_from_nodes/3 returns the current node" do
    assert node() === CallDirect.choose_from_nodes(:test_lb, [:other_node])
  end

  test "choose_from_nodes/3 ignores opts" do
    assert node() === CallDirect.choose_from_nodes(:test_lb, [:other_node], key: "some_key")
  end
end
