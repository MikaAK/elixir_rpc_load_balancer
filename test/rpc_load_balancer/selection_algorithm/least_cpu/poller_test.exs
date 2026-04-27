defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.PollerTest do
  use ExUnit.Case, async: true
  use RpcLoadBalancer.CacheCase

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller

  defp start_poller!(name, opts \\ []) do
    default_opts = [load_balancer_name: name, poll_interval: 100, poll_startup_jitter: 0]
    start_supervised!({Poller, Keyword.merge(default_opts, opts)}, id: name)
    name
  end

  defp poll_until(fun, attempts \\ 40, sleep_ms \\ 50) do
    case fun.() do
      nil when attempts > 0 ->
        Process.sleep(sleep_ms)
        poll_until(fun, attempts - 1, sleep_ms)

      nil ->
        nil

      value ->
        value
    end
  end

  defp await_cpu_entry(name) do
    entry =
      poll_until(fn ->
        case NodeCpuCache.get_local_cpu() do
          {:ok, %{} = map} -> map
          _ -> nil
        end
      end)

    entry || flunk("cache entry for #{inspect(name)} not populated within 2s")
  end

  defp await_entry_after(name, prev_fetched_at) do
    entry =
      poll_until(fn ->
        case NodeCpuCache.get_local_cpu() do
          {:ok, %{fetched_at: ts} = map} when ts > prev_fetched_at -> map
          _ -> nil
        end
      end)

    entry || flunk("no tick overwrote fetched_at for #{inspect(name)} within 2s")
  end

  test "writes local CPU metric from :cpu_sup to NodeCpuCache" do
    name = start_poller!(:poller_local)
    entry = await_cpu_entry(name)

    assert is_float(entry.cpu)
    assert entry.cpu >= 0.0 and entry.cpu <= 100.0
    assert is_integer(entry.fetched_at)
  end

  test "updates local CPU metric on subsequent ticks" do
    name = start_poller!(:poller_ticks, poll_interval: 50)
    first = await_cpu_entry(name)
    later = await_entry_after(name, first.fetched_at)

    assert later.fetched_at > first.fetched_at
  end

  test "falls back to the sampler-failure default when cpu_sampler raises" do
    name =
      start_poller!(:poller_raise,
        cpu_sampler: fn -> raise "boom" end
      )

    entry = await_cpu_entry(name)
    assert entry.cpu === 50.0
  end

  test "falls back to the sampler-failure default when cpu_sampler exits" do
    name =
      start_poller!(:poller_exit,
        cpu_sampler: fn -> exit(:sampler_exit) end
      )

    entry = await_cpu_entry(name)
    assert entry.cpu === 50.0
  end

  test "falls back to the sampler-failure default when cpu_sampler returns non-number" do
    name =
      start_poller!(:poller_non_number,
        cpu_sampler: fn -> :unexpected end
      )

    entry = await_cpu_entry(name)
    assert entry.cpu === 50.0
  end

  test "honours a custom numeric sampler" do
    name = start_poller!(:poller_custom, cpu_sampler: fn -> 42 end)
    entry = await_cpu_entry(name)

    assert entry.cpu === 42.0
  end

  test "delays the initial poll when poll_startup_jitter is set" do
    name = :poller_jitter_delay

    start_supervised!(
      {Poller,
       [
         load_balancer_name: name,
         poll_interval: 100,
         poll_startup_jitter: :timer.seconds(30),
         cpu_sampler: fn -> 25 end
       ]},
      id: name
    )

    Process.sleep(150)
    assert {:ok, nil} = NodeCpuCache.get_local_cpu()
  end

  test "emits :telemetry span events on every poll" do
    handler_id = {__MODULE__, :telemetry_test}
    test_pid = self()

    :telemetry.attach_many(
      handler_id,
      [
        [:rpc_load_balancer, :least_cpu, :poll, :start],
        [:rpc_load_balancer, :least_cpu, :poll, :stop]
      ],
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    start_poller!(:poller_telemetry, cpu_sampler: fn -> 10 end)

    assert_receive {:telemetry, [:rpc_load_balancer, :least_cpu, :poll, :start],
                    _, %{load_balancer_name: :poller_telemetry}},
                   1_000

    assert_receive {:telemetry, [:rpc_load_balancer, :least_cpu, :poll, :stop],
                    %{duration: _}, %{load_balancer_name: :poller_telemetry}},
                   1_000
  end
end
