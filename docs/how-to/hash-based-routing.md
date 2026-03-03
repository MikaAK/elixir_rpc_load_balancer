# How to Use Hash-Based Routing

This guide shows you how to route requests to consistent nodes using the HashRing algorithm, so that the same key always lands on the same node (as long as the node set is stable).

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

The same key will always resolve to the same node given an unchanged node list. This is useful for session affinity, caching, and sharding workloads.

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

## Fallback behaviour

When no `:key` is provided, the HashRing algorithm falls back to random selection. This means you can use the same balancer for both keyed and unkeyed requests.

## How the hash works

The algorithm sorts the available nodes, then uses `:erlang.phash2(key, node_count)` to deterministically map the key to an index. When nodes join or leave the cluster, keys may remap to different nodes — this is a simple modular hash, not a full consistent hash ring with virtual nodes.

If you need minimal key redistribution on topology changes, consider implementing a custom algorithm with virtual nodes (see [How to write a custom selection algorithm](custom-selection-algorithm.md)).
