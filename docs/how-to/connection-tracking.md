# How to Use Connection-Tracking Algorithms

The Least Connections and Power of Two algorithms track active connection counts per node. This guide covers how to use them and handle the connection lifecycle correctly.

## Start with Least Connections

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :lc_balancer,
    selection_algorithm: SelectionAlgorithm.LeastConnections
  )
```

## How tracking works

When `choose_from_nodes/3` runs, it:

1. Reads each node's connection count from an ETS counter
2. Picks the node with the lowest count
3. Atomically increments that node's counter

When the call finishes, the counter must be decremented.

## Automatic release with the convenience API

`LoadBalancer.call/5` handles this for you. After the RPC completes (success or failure), it calls `release_node/2` to decrement the counter:

```elixir
{:ok, result} =
  RpcLoadBalancer.LoadBalancer.call(:lc_balancer, MyModule, :work, [arg])
```

## Manual release with select_node

If you use `select_node/2` directly, you are responsible for releasing the node:

```elixir
{:ok, selected} = RpcLoadBalancer.LoadBalancer.select_node(:lc_balancer)

try do
  {:ok, :erpc.call(selected, MyModule, :work, [arg])}
after
  RpcLoadBalancer.LoadBalancer.release_node(:lc_balancer, selected)
end
```

Always release in an `after` block to prevent counter leaks on errors.

## Power of Two

Power of Two works identically but samples only two random nodes instead of scanning all of them. It provides a good balance between accuracy and performance at scale:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :p2c_balancer,
    selection_algorithm: SelectionAlgorithm.PowerOfTwo
  )
```

The same release semantics apply — `LoadBalancer.call/5` handles it automatically, `select_node/2` requires manual `release_node/2`.

## Node lifecycle

Both algorithms implement `on_node_change/2`:

- **Join** — initializes a zero counter for the new node
- **Leave** — deletes the counter entry for the departed node

This happens automatically when the `:pg` group membership changes.
