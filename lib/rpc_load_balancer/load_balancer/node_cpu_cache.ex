defmodule RpcLoadBalancer.LoadBalancer.NodeCpuCache do
  @moduledoc """
  Per-load-balancer ETS cache for CPU metrics, keyed by node.

  Each load balancer gets its own named ETS table (derived from the LB
  name). Storage is the `Cache.ETS` adapter — the `use Cache` macro is
  not used because it hard-codes the table name at compile time, and
  per-LB tables need the name at runtime.

  `Cache.PersistentTerm` is unsuitable because the Poller writes every
  tick and `:persistent_term.put/2` triggers a global GC sweep of every
  process referencing the term table.
  """

  @type entry :: %{cpu: float(), fetched_at: integer()}

  @table_wait_ms 1_000

  @spec table_name(atom() | module()) :: atom()
  def table_name(load_balancer_name), do: :"#{load_balancer_name}_node_cpu_cache"

  @spec child_spec(atom() | module()) :: Supervisor.child_spec()
  def child_spec(load_balancer_name) do
    %{
      id: {__MODULE__, load_balancer_name},
      start: {__MODULE__, :start_link, [load_balancer_name]}
    }
  end

  @spec start_link(atom() | module()) :: {:ok, pid()} | {:error, any()}
  def start_link(load_balancer_name) do
    ets_opts = [
      table_name: table_name(load_balancer_name),
      type: :set,
      read_concurrency: true,
      write_concurrency: true
    ]

    with {:ok, pid} <- Cache.ETS.start_link(ets_opts),
         :ok <- await_table_ready(table_name(load_balancer_name)) do
      {:ok, pid}
    end
  end

  @spec put(atom() | module(), node(), entry()) :: :ok | {:error, ErrorMessage.t()}
  def put(load_balancer_name, target_node, entry) do
    Cache.ETS.put(table_name(load_balancer_name), target_node, nil, entry)
  end

  @spec get(atom() | module(), node()) ::
          {:ok, entry() | nil} | {:error, ErrorMessage.t()}
  def get(load_balancer_name, target_node) do
    Cache.ETS.get(table_name(load_balancer_name), target_node)
  end

  @spec delete(atom() | module(), node()) :: :ok | {:error, ErrorMessage.t()}
  def delete(load_balancer_name, target_node) do
    Cache.ETS.delete(table_name(load_balancer_name), target_node)
  end

  @doc """
  Reads the local node's cached CPU entry.

  Exposed as a dedicated function so `:erpc.multicall/5` can target it
  with a single argument list — the remote node resolves its own
  identity rather than the caller embedding it in the key.
  """
  @spec get_local(atom() | module()) ::
          {:ok, entry() | nil} | {:error, ErrorMessage.t()}
  def get_local(load_balancer_name), do: get(load_balancer_name, node())

  # `Cache.ETS.start_link/1` creates the table inside a `Task.start_link/1`,
  # so the table isn't guaranteed to exist by the time start_link returns.
  # Spin briefly until the adapter has registered the named table, so
  # callers can read and write immediately after supervision start.
  defp await_table_ready(table_name) do
    deadline = System.monotonic_time(:millisecond) + @table_wait_ms
    wait_for_table(table_name, deadline)
  end

  defp wait_for_table(table_name, deadline) do
    cond do
      :ets.info(table_name) !== :undefined ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        {:error, "NodeCpuCache ETS table #{inspect(table_name)} never created"}

      true ->
        Process.sleep(1)
        wait_for_table(table_name, deadline)
    end
  end
end
