defmodule RpcLoadBalancer.LoadBalancer do
  @moduledoc """
  GenServer responsible for joining the `:pg` group, monitoring membership
  changes, and performing graceful connection draining on shutdown.
  """

  use GenServer

  alias RpcLoadBalancer.LoadBalancer.Drainer
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  @pg_group_name RpcLoadBalancer.LoadBalancer.Pg.pg_group_name()

  @typep state :: %{
           algorithm: module(),
           node_match_list: [String.t() | Regex.t()] | :all,
           name: atom(),
           algorithm_opts: keyword(),
           pg_ref: reference() | nil,
           drain_timeout: timeout(),
           drainer_index: non_neg_integer() | nil
         }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    {node_match_list, opts} = Keyword.pop(opts, :node_match_list, :all)
    {algorithm_opts, opts} = Keyword.pop(opts, :algorithm_opts, [])
    {drain_timeout, opts} = Keyword.pop(opts, :drain_timeout, :timer.seconds(15))

    {selection_algorithm, _opts} =
      Keyword.pop(opts, :selection_algorithm, SelectionAlgorithm.Random)

    init_state = %{
      algorithm: selection_algorithm,
      node_match_list: node_match_list,
      name: name,
      algorithm_opts: algorithm_opts,
      pg_ref: nil,
      drain_timeout: drain_timeout,
      drainer_index: nil
    }

    GenServer.start_link(__MODULE__, init_state, name: :"#{name}_server")
  end

  @impl true
  @spec init(state()) :: {:ok, state(), {:continue, :register}}
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state, {:continue, :register}}
  end

  @impl true
  def handle_continue(:register, state) do
    alias RpcLoadBalancer.LoadBalancer.IndexRegistry

    IndexRegistry.init_counter(:rpc_lb_drainer_cache)
    IndexRegistry.init_counter(:rpc_lb_counter_cache)

    drainer_index = Drainer.register(state.name)

    :ok = SelectionAlgorithm.put_algorithm(state.name, state.algorithm)
    :ok = SelectionAlgorithm.init(state.algorithm, state.name, state.algorithm_opts)

    if included_node?(state.node_match_list, node()) do
      :ok = :pg.join(@pg_group_name, state.name, self())
    end

    pg_ref = monitor_pg_group(state.name)

    {:noreply, %{state | pg_ref: pg_ref, drainer_index: drainer_index}}
  end

  @impl true
  def handle_info({:pg, _ref, :join, _group, pids}, state) do
    nodes = pids |> Enum.map(&node/1) |> Enum.uniq()
    :ok = SelectionAlgorithm.on_node_change(state.algorithm, state.name, {:joined, nodes})
    {:noreply, state}
  end

  def handle_info({:pg, _ref, :leave, _group, pids}, state) do
    nodes = pids |> Enum.map(&node/1) |> Enum.uniq()
    :ok = SelectionAlgorithm.on_node_change(state.algorithm, state.name, {:left, nodes})
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if included_node?(state.node_match_list, node()) do
      try do
        :pg.leave(@pg_group_name, state.name, self())
      catch
        _, _ -> :ok
      end
    end

    _result =
      try do
        Drainer.drain(state.drainer_index, state.drain_timeout)
      catch
        _, _ -> :ok
      end

    :ok
  end

  defp included_node?(:all, _node_name), do: true

  defp included_node?(node_list, node_name) do
    Enum.any?(node_list, &(to_string(node_name) =~ &1))
  end

  defp monitor_pg_group(load_balancer_name) do
    if function_exported?(:pg, :monitor, 2) do
      :pg.monitor(@pg_group_name, load_balancer_name)
    else
      nil
    end
  end
end
