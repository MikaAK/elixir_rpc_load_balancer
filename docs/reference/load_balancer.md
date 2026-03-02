# Load Balancer

`RpcLoadBalancer.LoadBalancer` uses `:pg` to track the set of nodes which are ready to receive traffic for a given balancer name.

## Starting

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :my_balancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin
  )
```

## Selecting a node

```elixir
{:ok, node} = RpcLoadBalancer.LoadBalancer.select_node(:my_balancer)
```

## Convenience API

Combine node selection and RPC in a single call:

```elixir
{:ok, result} = RpcLoadBalancer.LoadBalancer.call(:my_balancer, MyModule, :my_fun, [arg1])
:ok = RpcLoadBalancer.LoadBalancer.cast(:my_balancer, MyModule, :my_fun, [arg1])
```

For hash-based routing, pass a `:key` option:

```elixir
{:ok, result} = RpcLoadBalancer.LoadBalancer.call(:my_balancer, MyModule, :my_fun, [arg1], key: "user:123")
```

## Algorithms

Built-in algorithms:

- **`SelectionAlgorithm.Random`** — picks a random node
- **`SelectionAlgorithm.RoundRobin`** — cycles through nodes using an atomic counter
- **`SelectionAlgorithm.LeastConnections`** — selects the node with fewest active connections
- **`SelectionAlgorithm.PowerOfTwo`** — picks 2 random nodes, selects the one with fewer connections
- **`SelectionAlgorithm.HashRing`** — consistent hash-based routing via a `:key` option
- **`SelectionAlgorithm.WeightedRoundRobin`** — round robin with configurable per-node weights

### Weighted Round Robin

Pass weights via `algorithm_opts`:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :my_balancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobin,
    algorithm_opts: [weights: %{:"node1@host" => 3, :"node2@host" => 1}]
  )
```

## Custom Algorithms

Implement the `RpcLoadBalancer.LoadBalancer.SelectionAlgorithm` behaviour:

```elixir
@callback choose_from_nodes(load_balancer_name(), [node()], opts :: keyword()) :: node()
```

Optional lifecycle callbacks:

```elixir
@callback init(load_balancer_name(), opts :: keyword()) :: :ok
@callback on_node_change(load_balancer_name(), {:joined | :left, [node()]}) :: :ok
@callback release_node(load_balancer_name(), node()) :: :ok
```
