defmodule RpcLoadBalancer.LoadBalancer.NodeCpuCacheTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache

  defp start_cache!(name) do
    start_supervised!(NodeCpuCache.child_spec(name), id: {:ncc, name})
    name
  end

  test "child_spec/1 starts a per-LB ETS table named off the load balancer" do
    name = start_cache!(:ncc_table_naming)
    assert :ets.info(NodeCpuCache.table_name(name)) !== :undefined
  end

  test "put/get round-trip" do
    name = start_cache!(:ncc_roundtrip)
    entry = %{cpu: 42.0, fetched_at: System.monotonic_time(:millisecond)}
    :ok = NodeCpuCache.put(name, :some_node, entry)

    assert {:ok, ^entry} = NodeCpuCache.get(name, :some_node)
  end

  test "get/2 returns {:ok, nil} for an absent entry" do
    name = start_cache!(:ncc_missing)
    assert {:ok, nil} = NodeCpuCache.get(name, :never_written)
  end

  test "delete/2 removes the entry" do
    name = start_cache!(:ncc_delete)
    entry = %{cpu: 10.0, fetched_at: System.monotonic_time(:millisecond)}
    :ok = NodeCpuCache.put(name, :n, entry)
    :ok = NodeCpuCache.delete(name, :n)

    assert {:ok, nil} = NodeCpuCache.get(name, :n)
  end

  test "get_local/1 reads the entry keyed by the current node" do
    name = start_cache!(:ncc_local)
    entry = %{cpu: 25.0, fetched_at: System.monotonic_time(:millisecond)}
    :ok = NodeCpuCache.put(name, node(), entry)

    assert {:ok, ^entry} = NodeCpuCache.get_local(name)
  end

  test "tables are isolated per load balancer" do
    a = start_cache!(:ncc_iso_a)
    b = start_cache!(:ncc_iso_b)

    :ok = NodeCpuCache.put(a, :shared_key, %{cpu: 1.0, fetched_at: 0})

    assert {:ok, %{cpu: 1.0}} = NodeCpuCache.get(a, :shared_key)
    assert {:ok, nil} = NodeCpuCache.get(b, :shared_key)
  end
end
