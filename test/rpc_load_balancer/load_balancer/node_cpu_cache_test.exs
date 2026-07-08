defmodule RpcLoadBalancer.LoadBalancer.NodeCpuCacheTest do
  use ExUnit.Case, async: true
  use RpcLoadBalancer.CacheCase

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache

  test "put_cpu/get_cpu round-trip" do
    entry = %{cpu: 42.0, fetched_at: System.monotonic_time(:millisecond)}
    :ok = NodeCpuCache.put_cpu(:some_node, entry)

    assert NodeCpuCache.get_cpu(:some_node) === entry
  end

  test "get_cpu/1 returns nil for an absent entry" do
    assert NodeCpuCache.get_cpu(:never_written) === nil
  end

  test "delete_cpu/1 removes the entry" do
    entry = %{cpu: 10.0, fetched_at: System.monotonic_time(:millisecond)}
    :ok = NodeCpuCache.put_cpu(:to_delete, entry)
    :ok = NodeCpuCache.delete_cpu(:to_delete)

    assert NodeCpuCache.get_cpu(:to_delete) === nil
  end

  test "get_local_cpu/0 reads the entry keyed by the current node" do
    entry = %{cpu: 25.0, fetched_at: System.monotonic_time(:millisecond)}
    :ok = NodeCpuCache.put_cpu(node(), entry)

    assert NodeCpuCache.get_local_cpu() === entry
  end
end
