defmodule RpcLoadBalancer.LoadBalancer do
  @moduledoc """
  Distributed load balancer based on `:pg`.

  Nodes register themselves when started so callers can pick an available node
  using a selection algorithm.
  """

  use GenServer

  alias RpcLoadBalancer.LoadBalancer
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  @type node_match_list :: [String.t() | Regex.t()] | :all
  @type option ::
          {:node_match_list, node_match_list()}
          | {:selection_algorithm, module()}
          | {:algorithm_opts, keyword()}
  @type opts :: [GenServer.option() | option()]
  @type name :: atom() | module()

  @typep state :: %{
           algorithm: module(),
           node_match_list: [String.t() | Regex.t()] | :all,
           name: name(),
           algorithm_opts: keyword(),
           pg_ref: reference() | nil
         }

  @pg_group_name LoadBalancer.Pg.pg_group_name()

  @spec pg_group_name() :: atom()
  defdelegate pg_group_name, to: LoadBalancer.Pg

  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {node_match_list, opts} = Keyword.pop(opts, :node_match_list, :all)
    {algorithm_opts, opts} = Keyword.pop(opts, :algorithm_opts, [])

    {selection_algorithm, opts} =
      Keyword.pop(opts, :selection_algorithm, SelectionAlgorithm.Random)

    load_balancer_name = opts[:name] || random_load_balancer_name()

    opts = Keyword.put_new(opts, :name, load_balancer_name)

    init_state = %{
      algorithm: selection_algorithm,
      node_match_list: node_match_list,
      name: load_balancer_name,
      algorithm_opts: algorithm_opts,
      pg_ref: nil
    }

    GenServer.start_link(__MODULE__, init_state, opts)
  end

  @impl true
  @spec init(state()) :: {:ok, state(), {:continue, :register}}
  def init(state) do
    {:ok, state, {:continue, :register}}
  end

  @impl true
  def handle_continue(:register, state) do
    :ok = SelectionAlgorithm.put_algorithm(state.name, state.algorithm)
    :ok = SelectionAlgorithm.init(state.algorithm, state.name, state.algorithm_opts)

    if included_node?(state.node_match_list, node()) do
      :ok = :pg.join(@pg_group_name, state.name, self())
    end

    pg_ref = monitor_pg_group(state.name)

    {:noreply, %{state | pg_ref: pg_ref}}
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

  @doc """
  Selects a node from the available nodes for the load balancer.
  """
  @spec select_node(name(), keyword()) :: ErrorMessage.t_res(node())
  def select_node(load_balancer_name, opts \\ []) do
    with {:ok, node_list} <- get_members(load_balancer_name),
         {:ok, algorithm} <- SelectionAlgorithm.get_algorithm(load_balancer_name) do
      {:ok, SelectionAlgorithm.choose_from_nodes(algorithm, load_balancer_name, node_list, opts)}
    end
  end

  @doc """
  Releases a node after an RPC call completes.

  Used by connection-tracking algorithms (e.g., Least Connections) to
  decrement their active connection counters.
  """
  @spec release_node(name(), node()) :: :ok
  def release_node(load_balancer_name, node) do
    case SelectionAlgorithm.get_algorithm(load_balancer_name) do
      {:ok, algorithm} when not is_nil(algorithm) ->
        SelectionAlgorithm.release_node(algorithm, load_balancer_name, node)

      _ ->
        :ok
    end
  end

  @doc """
  Selects a node and executes an RPC call through the load balancer.
  """
  @spec call(name(), module(), atom(), [term()], keyword()) :: ErrorMessage.t_res(any())
  def call(load_balancer_name, module, fun, args, opts \\ []) do
    {select_opts, call_opts} = Keyword.split(opts, [:key])

    with {:ok, selected_node} <- select_node(load_balancer_name, select_opts) do
      result = RpcLoadBalancer.call(selected_node, module, fun, args, call_opts)
      release_node(load_balancer_name, selected_node)
      result
    end
  end

  @doc """
  Selects a node and executes an RPC cast through the load balancer.
  """
  @spec cast(name(), module(), atom(), [term()], keyword()) :: :ok | {:error, ErrorMessage.t()}
  def cast(load_balancer_name, module, fun, args, opts \\ []) do
    {select_opts, _cast_opts} = Keyword.split(opts, [:key])

    with {:ok, selected_node} <- select_node(load_balancer_name, select_opts) do
      RpcLoadBalancer.cast(selected_node, module, fun, args)
    end
  end

  @doc """
  Gets the nodes that are registered for the load balancer.
  """
  @spec get_members(name()) :: ErrorMessage.t_res([node()])
  def get_members(load_balancer_name) do
    case :pg.get_members(@pg_group_name, load_balancer_name) do
      [] ->
        {:error,
         ErrorMessage.service_unavailable(
           "no nodes online for load balancer",
           %{load_balancer_name: load_balancer_name}
         )}

      pids ->
        {:ok, pids |> Enum.map(&node/1) |> Enum.uniq()}
    end
  end

  defp included_node?(:all, _node_name), do: true

  defp included_node?(node_list, node_name) do
    Enum.any?(node_list, &(to_string(node_name) =~ &1))
  end

  defp random_load_balancer_name do
    random = :crypto.strong_rand_bytes(5) |> Base.encode16(case: :lower)
    String.to_atom("load_balancer_#{random}")
  end

  defp monitor_pg_group(load_balancer_name) do
    if function_exported?(:pg, :monitor, 2) do
      :pg.monitor(@pg_group_name, load_balancer_name)
    else
      nil
    end
  end
end
