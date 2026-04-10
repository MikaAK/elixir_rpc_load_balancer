defmodule RpcLoadBalancer.LoadBalancer.NodeCpuCache do
  @moduledoc """
  Cache for CPU metrics keyed by `{load_balancer_name, node}`.

  Stores `%{cpu: float(), fetched_at: integer()}` for both local and remote
  nodes. Written by `LeastCpu.Poller` and read by the `LeastCpu` algorithm
  during node selection.
  """

  use Cache,
    adapter: Cache.PersistentTerm,
    name: :rpc_lb_node_cpu_cache,
    sandbox?: false,
    opts: []
end
