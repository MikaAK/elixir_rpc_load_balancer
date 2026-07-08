defmodule RpcLoadBalancer.LoadBalancer.HashRingCache do
  @moduledoc """
  ETS-backed cache for the consistent hash ring built by
  `RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing`.

  Backed by `Cache.ETS` — not `:persistent_term` — because the ring is
  rewritten on every `on_node_change` event. In a large cluster
  (hundreds or thousands of nodes) at least one membership change is
  almost always in flight, so a `:persistent_term.put/2` per rebuild
  would mean continuous global GC sweeps. ETS writes are local,
  lock-free under `write_concurrency: true`, and trigger no GC.

  Reads use the macro-injected `lookup/1` (a direct `:ets.lookup/2`
  call) and writes use `insert_raw/1` instead of the telemetry-wrapped
  `Cache.get/1` and `Cache.put/3`. That skips both the
  `:telemetry.span/3` overhead and `Cache.TermEncoder` — the ring is
  several KB; round-tripping it through `:erlang.term_to_binary/1` on
  every put would dwarf the actual write cost.
  """

  use Cache,
    adapter: Cache.ETS,
    name: :rpc_lb_hash_ring_cache,
    sandbox?: Mix.env() === :test,
    opts: [type: :set, read_concurrency: true, write_concurrency: true]

  @spec put_ring(atom(), term()) :: :ok
  def put_ring(load_balancer_name, ring) do
    insert_raw({load_balancer_name, ring})
    :ok
  end

  @spec get_ring(atom()) :: term() | nil
  def get_ring(load_balancer_name) do
    case lookup(load_balancer_name) do
      [{_key, ring}] -> ring
      [] -> nil
    end
  end

  @spec delete_ring(atom()) :: :ok
  def delete_ring(load_balancer_name) do
    delete(load_balancer_name)
    :ok
  end
end
