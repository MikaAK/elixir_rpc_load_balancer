defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.PollerTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller

  defp start_poller!(name, opts \\ []) do
    default_opts = [
      load_balancer_name: name,
      poll_interval: 100,
      metric_source: :scheduler_utilization
    ]

    cache_children = [
      {Cache, [NodeCpuCache]}
    ]

    start_supervised!(%{
      id: :"#{name}_caches",
      start: {Supervisor, :start_link, [cache_children, [strategy: :one_for_one]]},
      type: :supervisor
    })

    start_supervised!({Poller, Keyword.merge(default_opts, opts)})
    Process.sleep(150)
    name
  end

  test "writes local CPU metric to NodeCpuCache" do
    name = start_poller!(:poller_local)

    assert {:ok, %{cpu: cpu, fetched_at: fetched_at}} =
             NodeCpuCache.get({name, node()})

    assert is_float(cpu)
    assert cpu >= 0.0 and cpu <= 100.0
    assert is_integer(fetched_at)
  end

  test "updates local CPU metric on subsequent ticks" do
    name = start_poller!(:poller_ticks, poll_interval: 50)

    {:ok, %{fetched_at: first_time}} = NodeCpuCache.get({name, node()})
    Process.sleep(100)
    {:ok, %{fetched_at: second_time}} = NodeCpuCache.get({name, node()})

    assert second_time > first_time
  end

  test "uses cpu_sup metric source when configured" do
    Application.ensure_all_started(:os_mon)
    name = start_poller!(:poller_cpu_sup, metric_source: :cpu_sup)

    assert {:ok, %{cpu: cpu}} = NodeCpuCache.get({name, node()})
    assert is_float(cpu)
    assert cpu >= 0.0 and cpu <= 100.0
  end
end
