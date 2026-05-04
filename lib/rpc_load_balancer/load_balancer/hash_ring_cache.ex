defmodule RpcLoadBalancer.LoadBalancer.HashRingCache do
  @moduledoc """
  ETS-backed cache for the consistent hash ring built by
  `RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing`.

  The ring is rebuilt on every `on_node_change` event, so storing it in
  `Cache.PersistentTerm` would trigger a global GC sweep on every
  topology change. ETS is the right backend for write-occasional,
  read-on-every-call state.

  Keyed by `load_balancer_name` — each LB owns one ring.
  """

  use Cache,
    adapter: Cache.ETS,
    name: :rpc_lb_hash_ring_cache,
    sandbox?: Mix.env() === :test,
    opts: [type: :set, read_concurrency: true, write_concurrency: true]

  @type ring :: term()

  @spec put_ring(atom(), ring()) :: :ok | {:error, ErrorMessage.t()}
  def put_ring(load_balancer_name, ring) do
    put(load_balancer_name, nil, ring)
  end

  @spec get_ring(atom()) :: {:ok, ring() | nil} | {:error, ErrorMessage.t()}
  def get_ring(load_balancer_name) do
    get(load_balancer_name)
  end

  @spec delete_ring(atom()) :: :ok | {:error, ErrorMessage.t()}
  def delete_ring(load_balancer_name) do
    delete(load_balancer_name)
  end
end
