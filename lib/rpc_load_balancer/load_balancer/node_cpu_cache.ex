defmodule RpcLoadBalancer.LoadBalancer.NodeCpuCache do
  @moduledoc """
  Shared ETS cache for CPU metrics, keyed by node.

  CPU utilization is a property of the node itself, not of any
  particular load balancer — every load balancer that contains a given
  node sees the same value. Storing one entry per node (rather than
  per `{load_balancer_name, target_node}`) deduplicates writes,
  simplifies the cache shape, and lets every Poller across every load
  balancer cooperate on warming the same data.

  Backed by `Cache.PersistentTerm` so the read path on every selection
  is a single `:persistent_term.get/2`. Writes (one per Poller tick)
  trigger a global GC sweep, but pollers run on the order of seconds
  and selection runs millions of times per second — the asymmetry is
  the right shape for `:persistent_term`. Test sandboxing flows
  through `Cache.SandboxRegistry`.
  """

  @cache_name :rpc_lb_node_cpu_cache

  use Cache,
    adapter: Cache.PersistentTerm,
    name: @cache_name,
    sandbox?: Mix.env() === :test,
    opts: []

  @type entry :: %{cpu: float(), fetched_at: integer()}

  @spec put_cpu(node(), entry()) :: :ok | {:error, ErrorMessage.t()}
  def put_cpu(target_node, entry) do
    put(target_node, nil, entry)
  end

  @doc """
  Read a node's cached CPU entry without telemetry overhead.

  Calls the configured cache adapter directly so per-node reads inside
  `LeastCpu.choose_from_nodes/3` don't pay `:telemetry.span/3` overhead
  for every node in the cluster. Returns `nil` when no entry exists,
  letting the caller fall back to a default.
  """
  @spec get_cpu(node()) :: entry() | nil
  def get_cpu(target_node) do
    case cache_adapter().get(@cache_name, target_node) do
      {:ok, nil} -> nil
      {:ok, value} -> Cache.TermEncoder.decode(value)
      _ -> nil
    end
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
  @spec get_local_cpu() :: entry() | nil
  def get_local_cpu, do: get_cpu(node())
end
