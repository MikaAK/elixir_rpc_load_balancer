# RpcLoadBalancer

An Elixir library for executing Remote Procedure Calls across distributed BEAM nodes with a built-in load balancer. It wraps Erlang's `:erpc` module with structured error handling and provides a pluggable node selection layer powered by OTP's `:pg` process groups.

## Features

- **RPC wrappers** — `call/5` and `cast/4` around `:erpc` with `ErrorMessage` error tuples
- **Distributed load balancer** — automatic node discovery and registration via `:pg`
- **Six selection algorithms** — Random, Round Robin, Least Connections, Power of Two, Hash Ring, Weighted Round Robin
- **Custom algorithms** — implement the `SelectionAlgorithm` behaviour to add your own
- **Node filtering** — restrict which nodes join a balancer with string or regex patterns
- **Connection tracking** — ETS-backed atomic counters for connection-aware algorithms

## Installation

Add `rpc_load_balancer` to your dependencies:

```elixir
def deps do
  [
    {:rpc_load_balancer, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Direct RPC

```elixir
{:ok, result} =
  RpcLoadBalancer.call(
    :"worker@host",
    MyModule,
    :some_fun,
    ["arg"],
    timeout: :timer.seconds(5)
  )

:ok = RpcLoadBalancer.cast(:"worker@host", MyModule, :some_fun, ["arg"])
```

### Load-Balanced RPC

Start a load balancer, then call through it:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :my_balancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin
  )

{:ok, result} = RpcLoadBalancer.LoadBalancer.call(:my_balancer, MyModule, :my_fun, [arg])
```

## Algorithms

| Algorithm | Description |
|---|---|
| `Random` | Picks a random node (default) |
| `RoundRobin` | Cycles through nodes with an atomic counter |
| `LeastConnections` | Selects the node with fewest active connections |
| `PowerOfTwo` | Picks 2 random nodes, chooses the one with fewer connections |
| `HashRing` | Consistent hash-based routing via a `:key` option |
| `WeightedRoundRobin` | Round robin with configurable per-node weights |

## Documentation

This project's documentation follows the [Diátaxis](https://diataxis.fr/) framework:

- **[Tutorial: Getting Started](docs/tutorials/getting-started.md)** — learn the library by building a load-balanced RPC setup step by step
- **[How-To Guides](docs/how-to/)** — solve specific problems like custom algorithms, node filtering, and hash-based routing
- **[Reference](docs/reference/)** — complete API documentation for every module
- **[Explanation](docs/explanation/architecture.md)** — understand the design decisions and internal architecture

## License

MIT — see [LICENSE](LICENSE) for details.
