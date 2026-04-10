defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.PollerTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller

  defp start_poller!(name, opts \\ []) do
    default_opts = [load_balancer_name: name, poll_interval: 100]
    start_supervised!({Poller, Keyword.merge(default_opts, opts)})
    name
  end

  defp await_cpu_entry(key) do
    waited =
      fn ->
        case NodeCpuCache.get(key) do
          {:ok, %{} = entry} ->
            entry

          _ ->
            Process.sleep(50)
            nil
        end
      end
      |> Stream.repeatedly()
      |> Stream.take(40)
      |> Enum.find(& &1)

    waited || flunk("cache entry #{inspect(key)} not populated within 2s")
  end

  defp await_entry_after(key, prev_fetched_at) do
    waited =
      fn ->
        case NodeCpuCache.get(key) do
          {:ok, %{fetched_at: ts} = entry} when ts > prev_fetched_at ->
            entry

          _ ->
            Process.sleep(25)
            nil
        end
      end
      |> Stream.repeatedly()
      |> Stream.take(40)
      |> Enum.find(& &1)

    waited || flunk("no tick overwrote fetched_at for #{inspect(key)} within 1s")
  end

  test "writes local CPU metric from :cpu_sup to NodeCpuCache" do
    name = start_poller!(:poller_local)
    entry = await_cpu_entry({name, node()})

    assert is_float(entry.cpu)
    assert entry.cpu >= 0.0 and entry.cpu <= 100.0
    assert is_integer(entry.fetched_at)
  end

  test "updates local CPU metric on subsequent ticks" do
    name = start_poller!(:poller_ticks, poll_interval: 50)
    first = await_cpu_entry({name, node()})
    later = await_entry_after({name, node()}, first.fetched_at)

    assert later.fetched_at > first.fetched_at
  end
end
