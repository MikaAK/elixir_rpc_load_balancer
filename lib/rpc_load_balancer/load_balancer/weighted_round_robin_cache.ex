defmodule RpcLoadBalancer.LoadBalancer.WeightedRoundRobinCache do
  @moduledoc """
  ETS-backed cache for the expanded weighted node list maintained by
  `RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobin`.

  The expanded list is `Enum.flat_map(node_list, &List.duplicate(&1, weight))`
  — rebuilt only when the running node membership changes. Storing it
  in ETS (not `:persistent_term`) means topology churn doesn't trigger
  global GC sweeps; in a large cluster with continuous flapping that
  would dominate.

  Hot-path reads use the macro-injected `lookup/1` (direct `:ets.lookup/2`)
  and writes use `insert_raw/1`, bypassing both the telemetry wrapper
  and `Cache.TermEncoder`.
  """

  use Cache,
    adapter: Cache.ETS,
    name: :rpc_lb_weighted_round_robin_cache,
    sandbox?: Mix.env() === :test,
    opts: [type: :set, read_concurrency: true, write_concurrency: true]

  @type entry :: {[node()], [node()]}

  @spec put_expanded(atom(), [node()], [node()]) :: :ok
  def put_expanded(load_balancer_name, node_list, expanded) do
    insert_raw({load_balancer_name, {node_list, expanded}})
    :ok
  end

  @spec get_expanded(atom()) :: entry() | nil
  def get_expanded(load_balancer_name) do
    case lookup(load_balancer_name) do
      [{_key, entry}] -> entry
      [] -> nil
    end
  end

  @spec delete_expanded(atom()) :: :ok
  def delete_expanded(load_balancer_name) do
    delete(load_balancer_name)
    :ok
  end
end
