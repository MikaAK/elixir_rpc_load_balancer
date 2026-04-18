defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller do
  @moduledoc """
  GenServer that periodically samples local CPU via `:cpu_sup` and fetches
  remote node CPU via `:erpc.multicall/5`, storing all results in
  `NodeCpuCache`.

  Remote fetches run in parallel — `:erpc.multicall/5` applies the timeout
  per-call, so poll wall-time stays bounded by `@remote_timeout` regardless
  of cluster size.

  `:cpu_sup` (from `:os_mon`) is used instead of scheduler wall time because
  enabling `:erlang.system_flag(:scheduler_wall_time, true)` is a VM-wide
  side effect with measurable overhead. `:os_mon` samples the OS directly
  and introduces no global BEAM flag.

  ## Telemetry

  Events are emitted under the `[:rpc_load_balancer, :least_cpu, :poll]`
  prefix and can be attached via `:telemetry` or wired into
  `Telemetry.Metrics` by downstream applications.

    * `[:rpc_load_balancer, :least_cpu, :poll, :start | :stop | :exception]`
      — span around a full poll cycle (local sample + remote fetches).
      Metadata: `%{load_balancer_name: name}`.
    * `[:rpc_load_balancer, :least_cpu, :poll, :remote_error]`
      — emitted for each remote that failed within a multicall cycle.
      Measurements: `%{count: 1}`.
      Metadata: `%{load_balancer_name: name, node: remote_node, kind: :exit | :error}`.
      `:exit` covers connectivity-class failures (timeout, noconnection);
      `:error` covers remote raises and unexpected shapes.
  """

  use GenServer

  require Logger

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache

  @pg_group_name RpcLoadBalancer.LoadBalancer.Pg.pg_group_name()

  @default_poll_interval 5_000
  # Fallback CPU percent written into cache when the sampler fails.
  # Semantically distinct from `LeastCpu.@default_cpu` — that one is the
  # cache-miss default used at selection time; this one is the sampling
  # failure default used at write time.
  @default_sampler_fallback 50.0
  @remote_timeout :timer.seconds(2)

  @type sampler :: (-> number())

  @type state :: %{
          load_balancer_name: atom() | module(),
          poll_interval: pos_integer(),
          cpu_sampler: sampler()
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
      poll_interval: Keyword.get(opts, :poll_interval, @default_poll_interval),
      cpu_sampler: Keyword.get(opts, :cpu_sampler, &default_cpu_sampler/0)
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
    :telemetry.span(
      [:rpc_load_balancer, :least_cpu, :poll],
      %{load_balancer_name: state.load_balancer_name},
      fn ->
        sample_and_store_local(state)
        poll_remote_nodes(state)
        {:ok, %{load_balancer_name: state.load_balancer_name}}
      end
    )

    schedule_next_poll(state.poll_interval)
  end

  defp schedule_next_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp sample_and_store_local(state) do
    cpu = sample_local_cpu(state.cpu_sampler)
    store_cpu(state.load_balancer_name, node(), cpu)
  end

  defp poll_remote_nodes(state) do
    case remote_members(state.load_balancer_name) do
      [] -> :ok
      remotes -> fetch_and_store_remotes(state.load_balancer_name, remotes)
    end
  end

  defp fetch_and_store_remotes(load_balancer_name, remotes) do
    remotes
    |> :erpc.multicall(NodeCpuCache, :get_local, [load_balancer_name], @remote_timeout)
    |> Enum.zip(remotes)
    |> Enum.each(fn {result, remote_node} ->
      handle_remote_result(result, load_balancer_name, remote_node)
    end)
  end

  defp handle_remote_result({:ok, {:ok, %{cpu: cpu}}}, load_balancer_name, remote_node) do
    store_cpu(load_balancer_name, remote_node, cpu)
  end

  defp handle_remote_result({:ok, _other}, _load_balancer_name, _remote_node), do: :ok

  defp handle_remote_result({:error, {:erpc, reason}}, load_balancer_name, remote_node) do
    log_remote_failure(remote_node, reason)
    emit_remote_error(load_balancer_name, remote_node, erpc_kind(reason))
  end

  defp handle_remote_result({:error, reason}, load_balancer_name, remote_node) do
    log_remote_failure(remote_node, reason)
    emit_remote_error(load_balancer_name, remote_node, :error)
  end

  defp handle_remote_result({:throw, value}, load_balancer_name, remote_node) do
    log_remote_failure(remote_node, {:throw, value})
    emit_remote_error(load_balancer_name, remote_node, :error)
  end

  defp erpc_kind(:timeout), do: :exit
  defp erpc_kind(:noconnection), do: :exit
  defp erpc_kind(_), do: :error

  defp log_remote_failure(remote_node, reason) do
    Logger.debug(
      "#{__MODULE__}: remote CPU fetch failed, node: #{inspect(remote_node)}, reason: #{inspect(reason)}"
    )
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
  end

  defp emit_remote_error(load_balancer_name, remote_node, kind) do
    :telemetry.execute(
      [:rpc_load_balancer, :least_cpu, :poll, :remote_error],
      %{count: 1},
      %{load_balancer_name: load_balancer_name, node: remote_node, kind: kind}
    )
  end

  defp sample_local_cpu(sampler) do
    case sampler.() do
      percent when is_number(percent) -> percent / 1.0
      _ -> @default_sampler_fallback
    end
  rescue
    exception ->
      Logger.warning(
        "#{__MODULE__}: cpu sampler raised, exception: #{inspect(exception)}"
      )

      @default_sampler_fallback
  catch
    :exit, reason ->
      Logger.warning("#{__MODULE__}: cpu sampler exited, reason: #{inspect(reason)}")
      @default_sampler_fallback
  end

  defp default_cpu_sampler, do: :cpu_sup.util()
end
