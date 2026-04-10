defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller do
  @moduledoc """
  GenServer that periodically samples local CPU and fetches remote node
  CPU metrics via `:erpc`, storing all results in `NodeCpuCache`.
  """

  use GenServer

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache

  @pg_group_name RpcLoadBalancer.LoadBalancer.Pg.pg_group_name()
  @remote_timeout :timer.seconds(2)

  @type state :: %{
          load_balancer_name: atom(),
          poll_interval: pos_integer(),
          metric_source: :scheduler_utilization | :cpu_sup,
          prev_wall_time: list() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :load_balancer_name)
    GenServer.start_link(__MODULE__, opts, name: :"#{name}_cpu_poller")
  end

  @impl true
  def init(opts) do
    :erlang.system_flag(:scheduler_wall_time, true)

    state = %{
      load_balancer_name: Keyword.fetch!(opts, :load_balancer_name),
      poll_interval: Keyword.get(opts, :poll_interval, 5_000),
      metric_source: Keyword.get(opts, :metric_source, :scheduler_utilization),
      prev_wall_time: :erlang.statistics(:scheduler_wall_time)
    }

    {:ok, state, {:continue, :poll}}
  end

  @impl true
  def handle_continue(:poll, state) do
    new_state = sample_and_store_local(state)
    poll_remote_nodes(new_state)
    schedule_poll(new_state.poll_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state = sample_and_store_local(state)
    poll_remote_nodes(new_state)
    schedule_poll(new_state.poll_interval)
    {:noreply, new_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp sample_and_store_local(state) do
    {cpu, new_state} = sample_cpu(state)
    now = System.monotonic_time(:millisecond)

    NodeCpuCache.put(
      {state.load_balancer_name, node()},
      nil,
      %{cpu: cpu, fetched_at: now}
    )

    new_state
  end

  defp poll_remote_nodes(state) do
    remote_nodes = get_remote_members(state.load_balancer_name)

    Enum.each(remote_nodes, fn remote_node ->
      case fetch_remote_cpu(state.load_balancer_name, remote_node) do
        {:ok, %{cpu: cpu}} ->
          now = System.monotonic_time(:millisecond)

          NodeCpuCache.put(
            {state.load_balancer_name, remote_node},
            nil,
            %{cpu: cpu, fetched_at: now}
          )

        _error ->
          :ok
      end
    end)
  end

  defp get_remote_members(load_balancer_name) do
    @pg_group_name
    |> :pg.get_members(load_balancer_name)
    |> Enum.map(&node/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 === node()))
  catch
    _, _ -> []
  end

  defp fetch_remote_cpu(load_balancer_name, remote_node) do
    :erpc.call(
      remote_node,
      NodeCpuCache,
      :get,
      [{load_balancer_name, remote_node}],
      @remote_timeout
    )
  catch
    _, _ -> :error
  end

  defp sample_cpu(%{metric_source: :scheduler_utilization, prev_wall_time: prev} = state) do
    current = :erlang.statistics(:scheduler_wall_time)
    cpu = compute_scheduler_utilization(prev, current)
    {cpu, %{state | prev_wall_time: current}}
  end

  defp sample_cpu(%{metric_source: :cpu_sup} = state) do
    cpu =
      try do
        case apply(:cpu_sup, :util, []) do
          percent when is_number(percent) -> percent / 1.0
          _ -> 50.0
        end
      catch
        _, _ -> 50.0
      end

    {cpu, state}
  end

  defp compute_scheduler_utilization(prev, current) do
    prev_map = Map.new(prev, fn {id, active, total} -> {id, {active, total}} end)

    {sum, count} =
      Enum.reduce(current, {0.0, 0}, fn {id, active, total}, {sum, n} ->
        case Map.fetch(prev_map, id) do
          {:ok, {prev_active, prev_total}} ->
            delta_total = total - prev_total

            if delta_total > 0 do
              utilization = (active - prev_active) / delta_total
              {sum + utilization, n + 1}
            else
              {sum, n}
            end

          :error ->
            {sum, n}
        end
      end)

    if count > 0, do: sum / count * 100.0, else: 50.0
  end
end
