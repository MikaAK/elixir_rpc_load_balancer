defmodule RpcLoadBalancer.LoadBalancer.NodeCpuCache do
  @moduledoc """
  Shared ETS cache for CPU metrics, keyed by `{load_balancer_name, target_node}`.

  Backed by `Cache.ETS` so the cache is one named table for the entire
  VM. Per-load-balancer isolation is achieved through the composite key
  rather than per-LB tables — this keeps the cache module compatible
  with the `use Cache` macro (which fixes the cache name at compile
  time) and lets test sandboxing flow through `Cache.SandboxRegistry`.

  `Cache.PersistentTerm` is unsuitable because the Poller writes every
  tick and `:persistent_term.put/2` triggers a global GC sweep of every
  process referencing the term table.
  """

  use Cache,
    adapter: Cache.ETS,
    name: :rpc_lb_node_cpu_cache,
    sandbox?: Mix.env() === :test,
    opts: [type: :set, read_concurrency: true, write_concurrency: true]

  @type entry :: %{cpu: float(), fetched_at: integer()}

  @spec put_cpu(atom() | module(), node(), entry()) :: :ok | {:error, ErrorMessage.t()}
  def put_cpu(load_balancer_name, target_node, entry) do
    put({load_balancer_name, target_node}, nil, entry)
  end

  @spec get_cpu(atom() | module(), node()) ::
          {:ok, entry() | nil} | {:error, ErrorMessage.t()}
  def get_cpu(load_balancer_name, target_node) do
    get({load_balancer_name, target_node})
  end

  @spec delete_cpu(atom() | module(), node()) :: :ok | {:error, ErrorMessage.t()}
  def delete_cpu(load_balancer_name, target_node) do
    delete({load_balancer_name, target_node})
  end

  @doc """
  Reads the local node's cached CPU entry.

  Exposed as a dedicated function so `:erpc.multicall/5` can target it
  with a single argument list — the remote node resolves its own
  identity rather than the caller embedding it in the key.
  """
  @spec get_local_cpu(atom() | module()) ::
          {:ok, entry() | nil} | {:error, ErrorMessage.t()}
  def get_local_cpu(load_balancer_name), do: get_cpu(load_balancer_name, node())
end
