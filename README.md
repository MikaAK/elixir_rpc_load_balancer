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

- **RPC wrappers** — `call/5` and `cast/5` around `:erpc` with `ErrorMessage` error tuples
- **Distributed load balancer** — automatic node discovery and registration via `:pg`
- **Seven selection algorithms** — Random, Round Robin, Least Connections, Power of Two, Hash Ring, Weighted Round Robin, Call Direct
- **Custom algorithms** — implement the `SelectionAlgorithm` behaviour to add your own
- **Node filtering** — restrict which nodes join a balancer with string or regex patterns
- **Connection tracking** — atomic counters for connection-aware algorithms
- **Random-node helpers** — `call_on_random_node/5` and `cast_on_random_node/5` for name-based node filtering with built-in retry
- **Graceful draining** — in-flight call tracking and connection draining on shutdown
- **Configurable retry** — automatic retry with configurable count and sleep when no nodes are available

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

Start a load balancer, then route calls through it with the `:load_balancer` option:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :my_balancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin
  )

{:ok, result} =
  RpcLoadBalancer.call(node(), MyModule, :my_fun, [arg], load_balancer: :my_balancer)
```

When the `:load_balancer` option is present, the first argument (node) is ignored — the balancer selects the target node for you.

> **Supervision tree ordering:** The load balancer should be the **last child** in your supervision tree. OTP shuts down children in reverse order, so placing it last means it shuts down first during deployment — the node deregisters from the `:pg` group and drains in-flight calls before your application logic stops.
>
> ```elixir
> children = [
>   MyApp.Repo,
>   MyApp.Endpoint,
>   {RpcLoadBalancer,
>    name: :my_balancer,
>    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin}
> ]
> ```

## Algorithms

| Algorithm | Description | Selection cost (8 nodes) | Scales with cluster size |
|---|---|---:|---|
| `CallDirect` | Executes locally via `apply/3`, bypassing `:erpc` — ideal for tests | **0.04 μs** / 23.2 M ips | constant |
| `Random` | Picks a random node (default) | **0.11 μs** / 8.7 M ips | constant |
| `RoundRobin` | Cycles through nodes with an atomic counter | **0.77 μs** / 1.29 M ips | constant |
| `WeightedRoundRobin` | Round robin with configurable per-node weights | **0.88 μs** / 1.14 M ips | constant (cached expanded list) |
| `LeastConnections` | Selects the node with fewest active connections | **1.18 μs** / 840 K ips | linear (`:counters` read per node) |
| `PowerOfTwo` | Picks 2 random nodes, chooses the one with fewer connections | **1.32 μs** / 760 K ips | sub-linear (2 `:counters` reads) |
| `HashRing` | Consistent hash-based routing via a `:key` option | **2.02 μs** / 490 K ips | near-constant (cached ring) |
| `LeastCpu` | Selects the node with the lowest cached CPU utilization | **12.0 μs** / 83 K ips | linear (CPU entry read per node) |

Numbers from `mix run bench/select_node_bench.exs` on Apple M1 Max,
Elixir 1.19.5 / OTP 28.3.3, 8-node synthetic cluster, single process.
Full per-cluster-size numbers, parallel-contention results (32
schedulers), and the optimization writeup are in
[`bench/README.md`](bench/README.md).

> **Picking an algorithm.** `Random`, `RoundRobin`, and `HashRing`
> are all sub-microsecond and constant-time regardless of cluster
> size — pick the one whose distribution semantics match your
> workload. `PowerOfTwo` is a good fit once the cluster grows past
> ~8 nodes and you want connection-aware balancing without paying
> for an O(N) scan; it delivers near-identical distribution to
> `LeastConnections` at a fraction of the cost. `LeastCpu` is the
> most expensive single-process option but routes around hot
> backends — use it when CPU pressure is the dominant load signal.

## Configuration

All values are optional and can be set via application config:

```elixir
config :rpc_load_balancer,
  call_directly?: false,
  retry?: true,
  retry_count: 5
```

| Key | Default | Description |
|-----|---------|-------------|
| `:call_directly?` | `false` | Execute all load-balanced calls locally via `apply/3` |
| `:retry?` | `true` | Enable automatic retry when no nodes are available |
| `:retry_count` | `5` | Maximum number of retries |

## Testing

In tests you typically don't have a multi-node cluster. Use the `CallDirect` algorithm so the load balancer executes calls locally instead of through `:erpc`:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :my_balancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirect
  )

{:ok, result} =
  RpcLoadBalancer.call(node(), MyModule, :my_fun, [arg], load_balancer: :my_balancer)
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
