# RpcLoadBalancer

An Elixir library for executing Remote Procedure Calls across distributed BEAM nodes with a built-in load balancer. It wraps Erlang's `:erpc` module with structured error handling and provides a pluggable node selection layer powered by OTP's `:pg` process groups.

## Why this exists

`Node.list/0` keeps crashed or unreachable nodes around until the net kernel's heartbeat notices, and any RPC routed there hangs until it times out. `rpc_load_balancer` selects targets from `:pg` process groups instead: when a node dies its group members vanish immediately, so the balancer only ever picks nodes with a live, registered process — and callers get `{:error, %ErrorMessage{code: :service_unavailable}}` rather than a silent timeout when nothing is available.

## Features

- **RPC wrappers** — `call/5` and `cast/5` around `:erpc` with `ErrorMessage` error tuples
- **Distributed load balancer** — automatic node discovery and registration via `:pg`
- **Eight selection algorithms** — Random, Round Robin, Weighted Round Robin, Least Connections, Power of Two, Hash Ring, Least CPU, Call Direct
- **Named load balancer modules** — `use RpcLoadBalancer` binds a configuration to a module with its own `call/5`, `cast/5`, `select_node/1`, and `child_spec/1`
- **Custom algorithms** — implement the `SelectionAlgorithm` behaviour to add your own
- **Node filtering** — restrict which nodes join a balancer with string or regex patterns, plus filter-relative exclusions via `excluded_node_patterns`
- **Connection tracking** — lock-free `:counters` for connection-aware algorithms
- **Random-node helpers** — `call_on_random_node/5` and `cast_on_random_node/5` for name-based node filtering with built-in retry
- **Retry on no route** — load-balanced calls and random-node helpers back off and retry when the pool is empty
- **Graceful draining** — in-flight call tracking and connection draining on shutdown
- **Telemetry & metrics** — `:telemetry` spans on every call/cast, node-selection events, and ready-made `Telemetry.Metrics` definitions in `RpcLoadBalancer.Metrics`

## Installation

Add `rpc_load_balancer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rpc_load_balancer, "~> 0.3"}
  ]
end
```

## Quick Start

```elixir
# Direct RPC
{:ok, result} =
  RpcLoadBalancer.call(
    :"worker@host",
    MyModule,
    :some_fun,
    ["arg"],
    timeout: :timer.seconds(5)
  )

# Load-balanced RPC — the node argument is ignored, the balancer picks one
{:ok, _pid} = RpcLoadBalancer.start_link(name: :my_balancer)

{:ok, result} =
  RpcLoadBalancer.call(node(), MyModule, :my_fun, [arg], load_balancer: :my_balancer)
```

Or bind a configuration to a module:

```elixir
defmodule MyApp.LoadBalancer do
  use RpcLoadBalancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin
end

children = [MyApp.LoadBalancer]

{:ok, result} = MyApp.LoadBalancer.call(node(), MyModule, :my_fun, [arg])
```

## Documentation

This project's documentation follows the [Diátaxis](https://diataxis.fr/) framework:

### Tutorials

- [Getting Started](tutorials/getting-started.md) — learn the library by building a load-balanced RPC setup step by step

### How-To Guides

- [Define a Named Load Balancer Module](how-to/named-load-balancer-module.md)
- [Write a Custom Selection Algorithm](how-to/custom-selection-algorithm.md)
- [Use Hash-Based Routing](how-to/hash-based-routing.md)
- [Filter Which Nodes Join a Balancer](how-to/node-filtering.md)
- [Use Connection-Tracking Algorithms](how-to/connection-tracking.md)
- [Configure Weighted Round Robin](how-to/weighted-round-robin.md)
- [Route by CPU Load with LeastCpu](how-to/least-cpu.md)
- [Control Retry Behaviour](how-to/retry-behaviour.md)
- [Collect Telemetry and Metrics](how-to/telemetry-and-metrics.md)
- [Testing with CallDirect](how-to/testing-with-call-direct.md)

### Reference

- [Full API Reference](reference/load_balancer.md) — types, functions, callbacks, and internal modules

### Explanation

- [Architecture and Design Decisions](explanation/architecture.md) — how the components fit together and why
