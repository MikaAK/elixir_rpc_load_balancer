# rpc_load_balancer

Library for executing Remote Procedure Calls with a distributed node load balancer.

## Installation

Add `rpc_load_balancer` to your dependencies:

```elixir
def deps do
  [
    {:rpc_load_balancer, "~> 0.1.0"}
  ]
end
```

`rpc_load_balancer` uses [`error_message`](https://hex.pm/packages/error_message) for error returns.

## RPC wrappers

```elixir
{:ok, result} =
  RpcLoadBalancer.call(
    :"some_node@host",
    MyModule,
    :some_fun,
    ["arg"],
    timeout: :timer.seconds(5)
  )

:ok = RpcLoadBalancer.cast(:"some_node@host", MyModule, :some_fun, ["arg"])
```

## Load balancer

Start the application so the `:pg` group and caches are available, then start a load balancer instance:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :my_balancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin
  )
```

### Selecting a node

```elixir
{:ok, node} = RpcLoadBalancer.LoadBalancer.select_node(:my_balancer)
```

### Convenience API

Combine node selection and RPC in a single call:

```elixir
{:ok, result} = RpcLoadBalancer.LoadBalancer.call(:my_balancer, MyModule, :my_fun, [arg])
:ok = RpcLoadBalancer.LoadBalancer.cast(:my_balancer, MyModule, :my_fun, [arg])
```

### Algorithms

- **Random** — default, picks a random node
- **RoundRobin** — cycles through nodes with an atomic counter
- **LeastConnections** — selects the node with fewest active connections
- **PowerOfTwo** — picks 2 random nodes, chooses the one with fewer connections
- **HashRing** — consistent hash-based routing via a `:key` option
- **WeightedRoundRobin** — round robin with per-node weight configuration

See `docs/reference/load_balancer.md` for full API documentation.
