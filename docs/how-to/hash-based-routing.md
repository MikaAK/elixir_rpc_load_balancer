# How to Use Hash-Based Routing

This guide shows you how to route requests to consistent nodes using the `HashRing` algorithm, so that the same key always lands on the same node — even when the cluster topology changes.

## Start a balancer with HashRing

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :hash_balancer,
    selection_algorithm: SelectionAlgorithm.HashRing
  )
```

Or as a named module:

```elixir
defmodule MyApp.ShardRouter do
  use RpcLoadBalancer, selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing
end
```

## Route by key

Pass a `:key` option when selecting a node or making an RPC call. Any term works — it is hashed with `:erlang.phash2/2` by `libring`:

```elixir
{:ok, node} =
  RpcLoadBalancer.select_node(:hash_balancer, key: "user:123")
```

The same key will always resolve to the same node while membership is unchanged. This is useful for session affinity, per-key caches, sharded in-memory state, and serialising work on a key.

## Use with the RPC API

The `:key` option is one of the few options `call/5` and `cast/5` forward to the algorithm:

```elixir
{:ok, result} =
  RpcLoadBalancer.call(
    node(),
    MyCache,
    :get,
    ["user:123"],
    load_balancer: :hash_balancer,
    key: "user:123"
  )

# or, with a named module
{:ok, result} = MyApp.ShardRouter.call(node(), MyCache, :get, ["user:123"], key: "user:123")
```

## Fallback behaviour

When no `:key` is provided, `HashRing` falls back to random selection. This means you can use the same balancer for both keyed and unkeyed requests.

## Select replicas for a key

`HashRing` implements `choose_nodes/4`, which walks the ring from the key's primary shard to find `count` distinct physical nodes. There is no top-level wrapper for it; call the dispatch layer with the balancer's members:

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

with {:ok, algorithm} <- SelectionAlgorithm.get_algorithm(:hash_balancer),
     {:ok, members} <- RpcLoadBalancer.get_members(:hash_balancer) do
  [primary, replica] =
    SelectionAlgorithm.choose_nodes(algorithm, :hash_balancer, members, 2, key: "user:123")
end
```

The same key always maps to the same ordered set of nodes, which is what you want for replicated writes.

## Configure weight (virtual nodes)

Each physical node is placed on the ring multiple times as virtual nodes (shards). More shards means more uniform key distribution at the cost of a slightly larger ring. The default weight is 128 shards per physical node.

Override it via `algorithm_opts`:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :hash_balancer,
    selection_algorithm: SelectionAlgorithm.HashRing,
    algorithm_opts: [weight: 256]
  )
```

The weight is read once at `init/2` and stored in `:persistent_term`; changing it requires restarting the balancer.

## Topology stability

When nodes join or leave the cluster, only a minimal number of keys get redistributed. The majority of keys stay assigned to the same physical node.

For example, adding a 5th node to a 4-node cluster redistributes roughly 1/5 of keys (the ideal minimum), rather than reshuffling everything. Removing a node only moves the keys that were assigned to that node — keys on other nodes are unaffected.

## How the hash ring works

The `HashRing` algorithm is powered by [`libring`](https://hex.pm/packages/libring):

1. Each physical node is sharded into `weight` points (default 128) distributed across a `2^32` continuum
2. To look up a key, the key is hashed to a point on the ring, then the next shard clockwise determines the owning node
3. `choose_nodes/4` (`HashRing.key_to_nodes/3`) keeps walking to find N distinct physical nodes for replica selection
4. The built ring is cached in `RpcLoadBalancer.LoadBalancer.HashRingCache` — an ETS table read with a raw `:ets.lookup/2` so the hot path is one lookup plus a `libring` query
5. When membership changes, `on_node_change/2` deletes the cached ring; the next lookup lazily rebuilds it from the current member list, so a burst of joins/leaves costs one rebuild, not one per event

The ring lives in ETS rather than `:persistent_term` on purpose: it is rewritten on every membership change, and `:persistent_term.put/2` triggers a global GC sweep. In a large cluster where some node is almost always flapping, that would be a continuous tax; ETS writes are local and lock-free.
