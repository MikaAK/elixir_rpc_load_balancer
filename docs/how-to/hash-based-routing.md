# How to Use Hash-Based Routing

This guide shows you how to route requests to consistent nodes using the HashRing algorithm, so that the same key always lands on the same node — even when the cluster topology changes.

## Start a balancer with HashRing

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :hash_balancer,
    selection_algorithm: SelectionAlgorithm.HashRing
  )
```

## Route by key

Pass a `:key` option when selecting a node or making an RPC call:

```elixir
{:ok, node} =
  RpcLoadBalancer.LoadBalancer.select_node(:hash_balancer, key: "user:123")
```

The same key will always resolve to the same node. This is useful for session affinity, caching, and sharding workloads.

## Use with the convenience API

The `:key` option works with `call/5` and `cast/5` too:

```elixir
{:ok, result} =
  RpcLoadBalancer.LoadBalancer.call(
    :hash_balancer,
    MyCache,
    :get,
    ["user:123"],
    key: "user:123"
  )
```

## Select replica nodes

Use `select_nodes/3` to get multiple distinct nodes for a given key. This is useful for replication — the first node is the primary, the rest are replicas:

```elixir
{:ok, [primary, replica1, replica2]} =
  RpcLoadBalancer.LoadBalancer.select_nodes(:hash_balancer, 3, key: "user:123")
```

The same key always returns the same ordered set of nodes. If you request more nodes than are available, you get back all available nodes.

`select_nodes/3` works with any algorithm. Algorithms that don't implement `choose_nodes/4` fall back to returning randomly shuffled nodes.

## Fallback behaviour

When no `:key` is provided, both `select_node` and `select_nodes` fall back to random selection. This means you can use the same balancer for both keyed and unkeyed requests.

## Configure weight (virtual nodes)

Each physical node is placed on the ring multiple times as virtual nodes (shards). More shards means better key distribution uniformity at the cost of slightly more memory. The default weight is 128 shards per physical node.

Override it via `algorithm_opts`:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :hash_balancer,
    selection_algorithm: SelectionAlgorithm.HashRing,
    algorithm_opts: [weight: 256]
  )
```

## Topology stability

When nodes join or leave the cluster, only a minimal number of keys get redistributed. The majority of keys stay assigned to the same physical node.

For example, adding a 5th node to a 4-node cluster redistributes roughly 1/5 of keys (the ideal minimum), rather than reshuffling everything. Removing a node only moves the keys that were assigned to that node — keys on other nodes are unaffected.

## How the hash ring works

The HashRing algorithm is powered by [`libring`](https://hex.pm/packages/libring):

1. Each physical node is sharded into `weight` points (default 128) distributed across a `2^32` continuum using SHA-256
2. The ring is stored as a `gb_tree` in ETS for fast lookups
3. To look up a key, the key is hashed to a point on the ring, then the next highest shard clockwise determines the owning node
4. `key_to_nodes/3` walks the ring from that point to find N distinct physical nodes for replica selection
5. When topology changes, the ring is invalidated and lazily rebuilt on the next lookup
