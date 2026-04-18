defmodule RpcLoadBalancer.LoadBalancer.NodeCpuCacheTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache

  test "get_local/1 reads the entry keyed by {load_balancer_name, node()}" do
    entry = %{cpu: 42.0, fetched_at: System.monotonic_time(:millisecond)}
    NodeCpuCache.put({:ncc_local, node()}, nil, entry)

    assert {:ok, ^entry} = NodeCpuCache.get_local(:ncc_local)
  end

  test "get_local/1 returns {:ok, nil} for an absent entry" do
    assert {:ok, nil} = NodeCpuCache.get_local(:ncc_missing)
  end
end
