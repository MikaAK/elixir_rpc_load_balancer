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

Add `rpc_load_balancer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rpc_load_balancer, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
{:ok, result} =
  RpcLoadBalancer.call(
    :"worker@host",
    MyModule,
    :some_fun,
    ["arg"],
    timeout: :timer.seconds(5)
  )

{:ok, _pid} = RpcLoadBalancer.LoadBalancer.start_link(name: :my_balancer)
{:ok, result} = RpcLoadBalancer.LoadBalancer.call(:my_balancer, MyModule, :my_fun, [arg])
```

## Documentation

This project's documentation follows the [Diátaxis](https://diataxis.fr/) framework:

### Tutorials

- [Getting Started](tutorials/getting-started.md) — learn the library by building a load-balanced RPC setup step by step

### How-To Guides

- [Write a Custom Selection Algorithm](how-to/custom-selection-algorithm.md)
- [Use Hash-Based Routing](how-to/hash-based-routing.md)
- [Filter Which Nodes Join a Balancer](how-to/node-filtering.md)
- [Use Connection-Tracking Algorithms](how-to/connection-tracking.md)
- [Configure Weighted Round Robin](how-to/weighted-round-robin.md)

### Reference

- [Full API Reference](reference/load_balancer.md) — types, functions, callbacks, and internal modules

### Explanation

- [Architecture and Design Decisions](explanation/architecture.md) — how the components fit together and why
