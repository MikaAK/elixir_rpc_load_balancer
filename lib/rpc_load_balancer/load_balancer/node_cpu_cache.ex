defmodule RpcLoadBalancer.LoadBalancer.NodeCpuCache do
  @moduledoc """
  Cache for CPU metrics keyed by `{load_balancer_name, node}`.

  Stores `%{cpu: float(), fetched_at: integer()}` for both local and remote
  nodes. Written by `LeastCpu.Poller` and read by the `LeastCpu` algorithm
  during node selection.

  Backed by ETS — the Poller writes every tick, so a write-optimized adapter
  is required. `Cache.PersistentTerm` is unsuitable here because each write
  triggers a global GC sweep of every process referencing the term table.
  """

  use Cache,
    adapter: Cache.ETS,
    name: :rpc_lb_node_cpu_cache,
    sandbox?: false,
    opts: [read_concurrency: true, write_concurrency: true]

  @doc """
  Reads the local node's cached CPU entry for a given load balancer.

  Exposed as a dedicated function so `:erpc.multicall/5` can target it with a
  single argument list — the remote node resolves its own identity rather
  than the caller embedding it in the key.
  """
  @spec get_local(atom() | module()) ::
          {:ok, %{cpu: float(), fetched_at: integer()} | nil} | {:error, any()}
  def get_local(load_balancer_name), do: get({load_balancer_name, node()})
end
