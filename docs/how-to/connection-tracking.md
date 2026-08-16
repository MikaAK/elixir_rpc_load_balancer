# How to Use Connection-Tracking Algorithms

The `LeastConnections` and `PowerOfTwo` algorithms track active connection counts per node. This guide covers how to use them and handle the connection lifecycle correctly.

## Start with Least Connections

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :lc_balancer,
    selection_algorithm: SelectionAlgorithm.LeastConnections
  )
```

## How tracking works

Every node gets a lock-free `:counters` slot in the shared `CounterCache`, keyed by `{load_balancer_name, node}`. When `choose_from_nodes/3` runs, it:

1. Reads each node's connection count (a raw `:counters.get/2`, no telemetry or locks)
2. Picks the node with the lowest count in a single pass
3. Atomically increments that node's counter

When the call finishes, the counter must be decremented via `release_node/2`.

Selection and increment are not transactional — two concurrent callers can both read the same lowest count and pick the same node. That's fine: the increments are still atomic (no count is lost) and load balancing only needs to be approximately right.

## Automatic release with call/5 and cast/5

When you use `call/5` or `cast/5` with the `:load_balancer` option, the library handles counter management for you. After the RPC completes (success or failure), it calls the algorithm's `release_node/2` to decrement the counter:

```elixir
{:ok, result} =
  RpcLoadBalancer.call(node(), MyModule, :work, [arg], load_balancer: :lc_balancer)
```

Note that for `cast/5` the release happens as soon as `:erpc.cast/4` returns, not when the remote work finishes — casts are counted as connections only for the instant it takes to dispatch them.

## Manual release with select_node

If you use `select_node/2` directly, you are responsible for releasing the node through the algorithm:

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, selected} = RpcLoadBalancer.select_node(:lc_balancer)
{:ok, algorithm} = SelectionAlgorithm.get_algorithm(:lc_balancer)

try do
  {:ok, :erpc.call(selected, MyModule, :work, [arg])}
after
  SelectionAlgorithm.release_node(algorithm, :lc_balancer, selected)
end
```

Always release in an `after` block to prevent counter leaks on errors. A leaked increment permanently biases selection away from that node until it leaves and rejoins the group.

## Power of Two

`PowerOfTwo` works identically but samples only two random nodes instead of scanning all of them. It provides a good balance between accuracy and performance at scale — two `:counters` reads regardless of cluster size, with distribution close to `LeastConnections`:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :p2c_balancer,
    selection_algorithm: SelectionAlgorithm.PowerOfTwo
  )
```

The same release semantics apply — `call/5` and `cast/5` with `:load_balancer` handle it automatically, `select_node/2` requires manual release.

## Node lifecycle

Both algorithms implement `on_node_change/2`:

- **Join** — no-op (a node with no counter reads as 0, the natural "lowest" value)
- **Leave** — resets the counter for the departed node

This happens automatically when the `:pg` group membership changes.

## Choosing between them

| | `LeastConnections` | `PowerOfTwo` |
|---|---|---|
| Reads per selection | one per member (O(N)) | two |
| Cost at 8 nodes | ~1.2 μs | ~1.3 μs |
| Cost at 32 nodes | ~3.3 μs | ~2.0 μs |
| Distribution | exact minimum | near-minimum |

Prefer `LeastConnections` on small pools where exactness matters; switch to `PowerOfTwo` once the pool grows past roughly 8 nodes. Numbers from `bench/README.md`.
