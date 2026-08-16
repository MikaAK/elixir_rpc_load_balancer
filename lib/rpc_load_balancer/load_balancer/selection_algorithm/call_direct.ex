defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirect do
  @moduledoc """
  Selection algorithm that executes calls directly on the local node.

  When this algorithm is active, `RpcLoadBalancer.call/5` uses `apply/3`
  and `RpcLoadBalancer.cast/5` uses `spawn/3` instead of going through
  `:erpc`. Node selection is skipped entirely. Useful for development, testing, or single-node deployments
  where RPC overhead is unnecessary.
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  @impl true
  def local?, do: true

  @impl true
  def choose_from_nodes(_load_balancer_name, _node_list, _opts \\ []) do
    node()
  end
end
