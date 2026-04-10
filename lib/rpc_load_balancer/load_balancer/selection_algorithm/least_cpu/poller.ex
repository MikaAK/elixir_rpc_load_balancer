defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller do
  @moduledoc """
  GenServer that periodically samples local CPU via `:cpu_sup` and fetches
  remote node CPU via `:erpc`, storing all results in `NodeCpuCache`.

  `:cpu_sup` (from `:os_mon`) is used instead of scheduler wall time because
  enabling `:erlang.system_flag(:scheduler_wall_time, true)` is a VM-wide
  side effect with measurable overhead. `:os_mon` samples the OS directly
  and introduces no global BEAM flag.
  """

  use GenServer

  require Logger

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache

  @pg_group_name RpcLoadBalancer.LoadBalancer.Pg.pg_group_name()

  @default_poll_interval 5_000
  @default_cpu 50.0
  @remote_timeout :timer.seconds(2)

  @type state :: %{
          load_balancer_name: atom() | module(),
          poll_interval: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :load_balancer_name)
    GenServer.start_link(__MODULE__, opts, name: poller_name(name))
  end

  @spec poller_name(atom() | module()) :: atom()
  def poller_name(load_balancer_name) do
    :"#{load_balancer_name}_cpu_poller"
  end

  @impl true
  def init(opts) do
    state = %{
      load_balancer_name: Keyword.fetch!(opts, :load_balancer_name),
      poll_interval: Keyword.get(opts, :poll_interval, @default_poll_interval)
    }

    {:ok, state, {:continue, :poll}}
  end

  @impl true
  def handle_continue(:poll, state) do
    poll_and_schedule(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    poll_and_schedule(state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp poll_and_schedule(state) do
    sample_and_store_local(state)
    poll_remote_nodes(state)
    schedule_next_poll(state.poll_interval)
  end

  defp schedule_next_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp sample_and_store_local(state) do
    cpu = sample_local_cpu()
    store_cpu(state.load_balancer_name, node(), cpu)
  end

  defp poll_remote_nodes(state) do
    state.load_balancer_name
    |> remote_members()
    |> Enum.each(fn remote_node ->
      case fetch_remote_cpu(state.load_balancer_name, remote_node) do
        {:ok, %{cpu: cpu}} -> store_cpu(state.load_balancer_name, remote_node, cpu)
        _ -> :ok
      end
    end)
  end

  defp store_cpu(load_balancer_name, target_node, cpu) do
    NodeCpuCache.put(
      {load_balancer_name, target_node},
      nil,
      %{cpu: cpu, fetched_at: System.monotonic_time(:millisecond)}
    )
  end

  defp remote_members(load_balancer_name) do
    @pg_group_name
    |> :pg.get_members(load_balancer_name)
    |> Enum.map(&node/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 === node()))
  rescue
    exception ->
      Logger.warning(
        "#{__MODULE__}: failed to read :pg members, load_balancer: #{inspect(load_balancer_name)}, exception: #{inspect(exception)}"
      )

      []
  end

  defp fetch_remote_cpu(load_balancer_name, remote_node) do
    {:ok,
     :erpc.call(
       remote_node,
       NodeCpuCache,
       :get,
       [{load_balancer_name, remote_node}],
       @remote_timeout
     )}
  rescue
    exception in ErlangError ->
      Logger.debug(
        "#{__MODULE__}: remote CPU fetch failed, node: #{inspect(remote_node)}, exception: #{inspect(exception)}"
      )

      :error
  catch
    :exit, reason ->
      Logger.debug(
        "#{__MODULE__}: remote CPU fetch exited, node: #{inspect(remote_node)}, reason: #{inspect(reason)}"
      )

      :error
  end

  defp sample_local_cpu do
    case :cpu_sup.util() do
      percent when is_number(percent) -> percent / 1.0
      _ -> @default_cpu
    end
  rescue
    exception ->
      Logger.warning(
        "#{__MODULE__}: :cpu_sup.util/0 failed, exception: #{inspect(exception)}"
      )

      @default_cpu
  catch
    :exit, reason ->
      Logger.warning("#{__MODULE__}: :cpu_sup.util/0 exited, reason: #{inspect(reason)}")
      @default_cpu
  end
end
