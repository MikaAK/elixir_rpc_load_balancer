defmodule RpcLoadBalancer.LoadBalancer.NodeCpuCache do
  @moduledoc """
  Shared ETS cache for CPU metrics, keyed by node.

  CPU utilization is a property of the node itself, not of any
  particular load balancer — every load balancer that contains a given
  node sees the same value. Storing one entry per node (rather than
  per `{load_balancer_name, target_node}`) deduplicates writes,
  simplifies the cache shape, and lets every Poller across every load
  balancer cooperate on warming the same data.

  Backed by `Cache.ETS` so the cache is one named table for the entire
  VM. Test sandboxing flows through `Cache.SandboxRegistry`.

  `Cache.PersistentTerm` is unsuitable because the Poller writes every
  tick and `:persistent_term.put/2` triggers a global GC sweep of every
  process referencing the term table.
  """

  use Cache,
    adapter: Cache.PersistentTerm,
    name: :rpc_lb_node_cpu_cache,
    sandbox?: Mix.env() === :test,
    opts: [type: :set, read_concurrency: true, write_concurrency: true]

  @type entry :: %{cpu: float(), fetched_at: integer()}

  @spec put_cpu(node(), entry()) :: :ok | {:error, ErrorMessage.t()}
  def put_cpu(target_node, entry) do
    put(target_node, nil, entry)
  end

  @spec get_cpu(node()) :: {:ok, entry() | nil} | {:error, ErrorMessage.t()}
  def get_cpu(target_node) do
    get(target_node)
  end

  @spec delete_cpu(node()) :: :ok | {:error, ErrorMessage.t()}
  def delete_cpu(target_node) do
    delete(target_node)
  end

  @doc """
  Reads the local node's cached CPU entry.

  Exposed as a zero-arity function so `:erpc.multicall/5` can target it
  with an empty argument list — the remote node resolves its own
  identity rather than the caller embedding it in the key.
  """
  @spec get_local_cpu() :: {:ok, entry() | nil} | {:error, ErrorMessage.t()}
  def get_local_cpu, do: get_cpu(node())
end
