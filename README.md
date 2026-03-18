# RpcLoadBalancer
[![Hex version badge](https://img.shields.io/hexpm/v/rpc_load_balancer.svg)](https://hex.pm/packages/rpc_load_balancer)
[![Test](https://github.com/MikaAK/elixir_rpc_load_balancer/actions/workflows/test.yml/badge.svg)](https://github.com/MikaAK/elixir_rpc_load_balancer/actions/workflows/test.yml)
[![Credo](https://github.com/MikaAK/elixir_rpc_load_balancer/actions/workflows/credo.yml/badge.svg)](https://github.com/MikaAK/elixir_rpc_load_balancer/actions/workflows/credo.yml)
[![Dialyzer](https://github.com/MikaAK/elixir_rpc_load_balancer/actions/workflows/dialyzer.yml/badge.svg)](https://github.com/MikaAK/elixir_rpc_load_balancer/actions/workflows/dialyzer.yml)
[![Coverage](https://github.com/MikaAK/elixir_rpc_load_balancer/actions/workflows/coverage.yml/badge.svg)](https://github.com/MikaAK/elixir_rpc_load_balancer/actions/workflows/coverage.yml)


An Elixir library for executing Remote Procedure Calls across distributed BEAM nodes with a built-in load balancer. It wraps Erlang's `:erpc` module with structured error handling and provides a pluggable node selection layer powered by OTP's `:pg` process groups.

## Why This Exists

OTP's built-in node connection list (`Node.list/0`) does not automatically remove nodes that have crashed or become unreachable — they linger until the net kernel detects the failure, which can take seconds or longer depending on heartbeat configuration. During that window, any RPC call routed to the stale node will hang until it times out.

This library solves the problem by using `:pg` process groups instead of the raw node list. When a node goes down, its process group members are removed immediately because the backing processes exit. The load balancer only ever selects from nodes that have a live, registered process, so stale entries are never returned.

This gives you:

- **Instant removal** — dead nodes disappear from the selection pool as soon as their processes exit, with no timeout window
- **Accurate membership** — the node list always reflects actually reachable nodes
- **Structured errors** — instead of silent timeouts, callers get `{:error, %ErrorMessage{code: :service_unavailable}}` when no nodes are available

## Features

- **RPC wrappers** — `call/5` and `cast/4` around `:erpc` with `ErrorMessage` error tuples
- **Distributed load balancer** — automatic node discovery and registration via `:pg`
- **Seven selection algorithms** — Random, Round Robin, Least Connections, Power of Two, Hash Ring, Weighted Round Robin, Call Direct
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

> **Supervision tree ordering:** The load balancer should be the **last child** in your supervision tree. OTP shuts down children in reverse order, so placing it last means it shuts down first during deployment — this ensures the node deregisters from the `:pg` group before your application logic stops, preventing other nodes from routing calls to a node that is shutting down.
>
> ```elixir
> children = [
>   MyApp.Repo,
>   MyApp.Endpoint,
>   # ... other children ...
>   {RpcLoadBalancer.LoadBalancer,
>    name: :my_balancer,
>    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin}
> ]
> ```

## Algorithms

| Algorithm | Description |
|---|---|
| `Random` | Picks a random node (default) |
| `RoundRobin` | Cycles through nodes with an atomic counter |
| `LeastConnections` | Selects the node with fewest active connections |
| `PowerOfTwo` | Picks 2 random nodes, chooses the one with fewer connections |
| `HashRing` | Consistent hash-based routing via a `:key` option |
| `WeightedRoundRobin` | Round robin with configurable per-node weights |
| `CallDirect` | Executes locally via `apply/3`, bypassing `:erpc` — ideal for tests |

## Testing

In tests you typically don't have a multi-node cluster. Use the `CallDirect` algorithm so the load balancer executes calls locally instead of through `:erpc`:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :my_balancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirect
  )

# Calls run locally via apply/3
{:ok, result} = RpcLoadBalancer.LoadBalancer.call(:my_balancer, MyModule, :my_fun, [arg])
```

To switch automatically based on environment, use a compile-time module attribute:

```elixir
@selection_algorithm if Mix.env() === :test,
                       do: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirect,
                       else: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin
```

See the [Testing with CallDirect](docs/how-to/testing-with-call-direct.md) how-to guide for full examples.

## Documentation

This project's documentation follows the [Diátaxis](https://diataxis.fr/) framework:

- **[Tutorial: Getting Started](docs/tutorials/getting-started.md)** — learn the library by building a load-balanced RPC setup step by step
- **[How-To Guides](docs/how-to/)** — solve specific problems like custom algorithms, node filtering, and hash-based routing
- **[Reference](docs/reference/)** — complete API documentation for every module
- **[Explanation](docs/explanation/architecture.md)** — understand the design decisions and internal architecture

## License

MIT — see [LICENSE](LICENSE) for details.
