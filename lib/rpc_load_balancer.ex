defmodule RpcLoadBalancer do
  @moduledoc """
  Distributed RPC load balancer built on `:pg`.

  Acts as a per-instance Supervisor that starts the caches and GenServer
  needed for a single load balancer. Also provides the public API for
  node selection, RPC calls/casts, and low-level `:erpc` wrappers.

  ## Starting a load balancer

      RpcLoadBalancer.start_link(
        name: :my_lb,
        selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin,
        algorithm_opts: [weights: %{node() => 1}]
      )
  """

  use Supervisor

  alias RpcLoadBalancer.LoadBalancer.Drainer
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm
  alias RpcLoadBalancer.Retry

  @type name :: atom()

  @pg_group_name RpcLoadBalancer.LoadBalancer.Pg.pg_group_name()

  # -------------------------------------------------------------------
  # Supervisor
  # -------------------------------------------------------------------

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    algorithm = Keyword.get(opts, :selection_algorithm, SelectionAlgorithm.Random)
    algorithm_opts = Keyword.get(opts, :algorithm_opts, [])
    name = Keyword.fetch!(opts, :name)

    algorithm_children = SelectionAlgorithm.child_specs(algorithm, name, algorithm_opts)

    # Algorithm children (e.g. pollers) must start BEFORE the LoadBalancer
    # GenServer. Once LoadBalancer joins the :pg group, selection can happen,
    # so any algorithm-owned processes that produce data for selection
    # (CPU samples, counters, etc.) need to be up first.
    children =
      [
        {Cache,
         [
           RpcLoadBalancer.LoadBalancer.IndexRegistry,
           RpcLoadBalancer.LoadBalancer.AlgorithmCache,
           RpcLoadBalancer.LoadBalancer.ValueCache,
           RpcLoadBalancer.LoadBalancer.DrainerCache,
           RpcLoadBalancer.LoadBalancer.CounterCache
         ]}
      ] ++ algorithm_children ++ [
        {RpcLoadBalancer.LoadBalancer, opts}
      ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @spec get_members(name()) :: {:ok, [node()]} | {:error, ErrorMessage.t()}
  def get_members(load_balancer_name) do
    case :pg.get_members(@pg_group_name, load_balancer_name) do
      [] ->
        {:error,
         ErrorMessage.service_unavailable(
           "no members registered",
           %{load_balancer: load_balancer_name}
         )}

      pids ->
        nodes =
          pids
          |> Enum.map(&node/1)
          |> Enum.uniq()

        {:ok, nodes}
    end
  end

  @spec select_node(name(), keyword()) :: {:ok, node()} | {:error, ErrorMessage.t()}
  def select_node(load_balancer_name, opts \\ []) do
    with {:ok, algorithm} <- SelectionAlgorithm.get_algorithm(load_balancer_name),
         {:ok, members} <- get_members(load_balancer_name) do
      node = SelectionAlgorithm.choose_from_nodes(algorithm, load_balancer_name, members, opts)
      {:ok, node}
    end
  end

  # -------------------------------------------------------------------
  # :erpc wrappers
  # -------------------------------------------------------------------

  @spec call(node(), module(), atom(), [any()], keyword()) :: ErrorMessage.t_res(any())
  def call(node, module, fun, args, opts \\ [])

  def call(node, module, fun, args, opts) when is_atom(node) do
    load_balancer_name = Keyword.get(opts, :load_balancer)

    if load_balancer_name do
      lb_call(load_balancer_name, module, fun, args, opts)
    else
      erpc_call(node, module, fun, args, opts)
    end
  end

  @spec cast(node(), module(), atom(), [term()], keyword()) :: :ok | {:error, ErrorMessage.t()}
  def cast(node, module, fun, args, opts \\ [])

  def cast(node, module, fun, args, opts) when is_atom(node) do
    load_balancer_name = Keyword.get(opts, :load_balancer)

    if load_balancer_name do
      lb_cast(load_balancer_name, module, fun, args, opts)
    else
      erpc_cast(node, module, fun, args)
    end
  end

  defp lb_call(load_balancer_name, module, fun, args, opts) do
    call_directly? = Keyword.get(opts, :call_directly?, RpcLoadBalancer.Config.call_directly?())

    if call_directly? do
      {:ok, apply(module, fun, args)}
    else
      with {:ok, algorithm} <- SelectionAlgorithm.get_algorithm(load_balancer_name) do
        if SelectionAlgorithm.local?(algorithm) do
          {:ok, apply(module, fun, args)}
        else
          {select_opts, call_opts} = Keyword.split(opts, [:key, :call_directly?, :load_balancer])

          with {:ok, selected_node} <- select_node(load_balancer_name, select_opts) do
            with_drainer(load_balancer_name, fn ->
              result = erpc_call(selected_node, module, fun, args, call_opts)
              SelectionAlgorithm.release_node(algorithm, load_balancer_name, selected_node)
              result
            end)
          end
        end
      end
    end
  end

  defp lb_cast(load_balancer_name, module, fun, args, opts) do
    call_directly? = Keyword.get(opts, :call_directly?, RpcLoadBalancer.Config.call_directly?())

    if call_directly? do
      spawn(module, fun, args)
      :ok
    else
      with {:ok, algorithm} <- SelectionAlgorithm.get_algorithm(load_balancer_name) do
        if SelectionAlgorithm.local?(algorithm) do
          spawn(module, fun, args)
          :ok
        else
          {select_opts, _cast_opts} = Keyword.split(opts, [:key, :call_directly?, :load_balancer])

          with {:ok, selected_node} <- select_node(load_balancer_name, select_opts) do
            with_drainer(load_balancer_name, fn ->
              result = erpc_cast(selected_node, module, fun, args)
              SelectionAlgorithm.release_node(algorithm, load_balancer_name, selected_node)
              result
            end)
          end
        end
      end
    end
  end

  defp erpc_call(node, module, fun, args, opts) do
    timeout = Keyword.get(opts, :timeout, :timer.seconds(10))

    try do
      {:ok, :erpc.call(node, module, fun, args, timeout)}
    rescue
      e in ErlangError ->
        {:error, erlang_error_to_error_message(e, node)}

      e ->
        {:error, ErrorMessage.service_unavailable("unavailable", %{node: node, details: e})}
    end
  end

  defp erpc_cast(node, module, fun, args) do
    :erpc.cast(node, module, fun, args)
  rescue
    e in ErlangError ->
      {:error, erlang_error_to_error_message(e, node)}

    e ->
      {:error, ErrorMessage.service_unavailable("unavailable", %{node: node, details: e})}
  end

  # -------------------------------------------------------------------
  # Random-node helpers
  # -------------------------------------------------------------------

  @spec call_on_random_node(String.t(), module(), atom(), [any()], keyword()) ::
          ErrorMessage.t_res(any())
  def call_on_random_node(node_filter, module, fun, args, opts \\ []) do
    call_directly? = Keyword.get(opts, :call_directly?, RpcLoadBalancer.Config.call_directly?())
    load_balancer_name = Keyword.get(opts, :load_balancer)

    if call_directly? or current_node_matches_filter?(node_filter) do
      {:ok, apply(module, fun, args)}
    else
      no_nodes_error(Retry.with_retry(opts, fn ->
        case filter_nodes(node_filter) do
          [] ->
            :retry

          node_list ->
            selected_node = Enum.random(node_list)
            with_drainer(load_balancer_name, fn ->
              call(selected_node, module, fun, args, Keyword.take(opts, [:timeout]))
            end)
        end
      end), node_filter)
    end
  end

  @spec cast_on_random_node(String.t(), module(), atom(), [any()], keyword()) ::
          :ok | {:error, ErrorMessage.t()}
  def cast_on_random_node(node_filter, module, fun, args, opts \\ []) do
    call_directly? = Keyword.get(opts, :call_directly?, RpcLoadBalancer.Config.call_directly?())
    load_balancer_name = Keyword.get(opts, :load_balancer)

    if call_directly? or current_node_matches_filter?(node_filter) do
      spawn(module, fun, args)
      :ok
    else
      no_nodes_error(Retry.with_retry(opts, fn ->
        case filter_nodes(node_filter) do
          [] ->
            :retry

          node_list ->
            selected_node = Enum.random(node_list)
            with_drainer(load_balancer_name, fn ->
              cast(selected_node, module, fun, args)
            end)
        end
      end), node_filter)
    end
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp erlang_error_to_error_message(%ErlangError{original: {:erpc, :timeout}}, node) do
    ErrorMessage.request_timeout("timeout", %{node: node})
  end

  defp erlang_error_to_error_message(%ErlangError{original: {:erpc, :noconnection}}, node) do
    ErrorMessage.service_unavailable("noconnection", %{node: node})
  end

  defp erlang_error_to_error_message(%ErlangError{original: {:erpc, :badarg}}, node) do
    ErrorMessage.bad_request("bad request", %{node: node})
  end

  defp erlang_error_to_error_message(%ErlangError{} = error, _node) do
    ErrorMessage.service_unavailable("unavailable", %{details: error})
  end

  defp with_drainer(nil, fun), do: fun.()

  defp with_drainer(load_balancer_name, fun) do
    drainer_index = Drainer.register(load_balancer_name)
    Drainer.track_call(drainer_index)

    try do
      fun.()
    after
      Drainer.release_call(drainer_index)
    end
  end

  defp no_nodes_error(:error, node_filter) do
    {:error,
     ErrorMessage.service_unavailable(
       "no nodes in cluster found with that filter",
       %{node_filter: node_filter}
     )}
  end

  defp no_nodes_error(result, _node_filter), do: result

  defp filter_nodes(node_filter) do
    Enum.filter(Node.list(), &(to_string(&1) =~ node_filter))
  end

  defp current_node_matches_filter?(node_filter) do
    to_string(node()) =~ node_filter
  end
end
