defmodule RpcLoadBalancer.LoadBalancer.NodeCpuCacheTest do
  use ExUnit.Case, async: true
  use RpcLoadBalancer.CacheCase

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache

  test "put_cpu/get_cpu round-trip" do
    entry = %{cpu: 42.0, fetched_at: System.monotonic_time(:millisecond)}
    :ok = NodeCpuCache.put_cpu(:lb_round, :some_node, entry)

    assert {:ok, ^entry} = NodeCpuCache.get_cpu(:lb_round, :some_node)
  end

  test "get_cpu/2 returns {:ok, nil} for an absent entry" do
    assert {:ok, nil} = NodeCpuCache.get_cpu(:lb_missing, :never_written)
  end

  test "delete_cpu/2 removes the entry" do
    entry = %{cpu: 10.0, fetched_at: System.monotonic_time(:millisecond)}
    :ok = NodeCpuCache.put_cpu(:lb_delete, :n, entry)
    :ok = NodeCpuCache.delete_cpu(:lb_delete, :n)

    assert {:ok, nil} = NodeCpuCache.get_cpu(:lb_delete, :n)
  end

  test "get_local_cpu/1 reads the entry keyed by the current node" do
    entry = %{cpu: 25.0, fetched_at: System.monotonic_time(:millisecond)}
    :ok = NodeCpuCache.put_cpu(:lb_local, node(), entry)

    assert {:ok, ^entry} = NodeCpuCache.get_local_cpu(:lb_local)
  end

  test "entries are isolated per load balancer name" do
    :ok = NodeCpuCache.put_cpu(:lb_iso_a, :shared_key, %{cpu: 1.0, fetched_at: 0})

    assert {:ok, %{cpu: 1.0}} = NodeCpuCache.get_cpu(:lb_iso_a, :shared_key)
    assert {:ok, nil} = NodeCpuCache.get_cpu(:lb_iso_b, :shared_key)
  end
end
