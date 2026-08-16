# Tutorial: Getting Started with RpcLoadBalancer

This tutorial walks you through setting up `rpc_load_balancer` from scratch. By the end, you will have a working load balancer distributing RPC calls across BEAM nodes.

## What you'll build

A small Elixir application that:

1. Makes direct RPC calls to remote nodes
2. Runs a load balancer that automatically selects nodes
3. Uses a selection algorithm to control how nodes are picked
4. Wraps the configuration in a named module and supervises it

## Prerequisites

- Elixir 1.13+ / OTP 23+
- A Mix project

## Step 1: Add the dependency

Open your `mix.exs` and add `rpc_load_balancer`:

```elixir
def deps do
  [
    {:rpc_load_balancer, "~> 0.3"}
  ]
end
```

Fetch the dependency:

```bash
mix deps.get
```

The application starts automatically. It boots a `:pg` scope and the shared caches every load balancer relies on.

## Step 2: Make a direct RPC call

Before using the load balancer, try a direct RPC call. Open an IEx session:

```bash
iex -S mix
```

Call a function on the current node:

```elixir
{:ok, result} = RpcLoadBalancer.call(node(), String, :upcase, ["hello"])
```

You should see `{:ok, "HELLO"}`.

`call/5` wraps `:erpc.call/5` and returns `{:ok, result}` on success or `{:error, %ErrorMessage{}}` on failure. The default timeout is 10 seconds; override it with the `:timeout` option:

```elixir
{:ok, result} = RpcLoadBalancer.call(node(), String, :upcase, ["hello"], timeout: :timer.seconds(5))
```

For fire-and-forget calls, use `cast/5`:

```elixir
:ok = RpcLoadBalancer.cast(node(), IO, :puts, ["hello from cast"])
```

## Step 3: Start a load balancer

Now start a load balancer instance. `RpcLoadBalancer.start_link/1` starts a small Supervisor for a single balancer; its `LoadBalancer` GenServer registers the current node in a `:pg` group under the balancer's name:

```elixir
{:ok, _pid} = RpcLoadBalancer.start_link(name: :my_balancer)
```

The balancer uses the `Random` algorithm by default. Verify it's running by inspecting membership and selecting a node:

```elixir
{:ok, [member]} = RpcLoadBalancer.get_members(:my_balancer)
{:ok, selected} = RpcLoadBalancer.select_node(:my_balancer)
```

Since you're running a single node, both return your current node.

## Step 4: Make load-balanced RPC calls

Pass the `:load_balancer` option to `call/5` or `cast/5` to route through the balancer. The library selects a node using the configured algorithm, executes the RPC call, and returns the result:

```elixir
{:ok, result} =
  RpcLoadBalancer.call(node(), String, :reverse, ["hello"], load_balancer: :my_balancer)
```

For fire-and-forget:

```elixir
:ok = RpcLoadBalancer.cast(node(), IO, :puts, ["load balanced cast"], load_balancer: :my_balancer)
```

When the `:load_balancer` option is present, the first argument (node) is ignored — the balancer selects the target node for you.

If no member is registered yet (for example, during cluster boot), the call backs off and retries for you — 5 attempts, 5 seconds apart by default — before returning `{:error, %ErrorMessage{code: :service_unavailable}}`. See [Control Retry Behaviour](../how-to/retry-behaviour.md) to tune that.

## Step 5: Choose a selection algorithm

Start a second load balancer with Round Robin:

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :round_robin_balancer,
    selection_algorithm: SelectionAlgorithm.RoundRobin
  )
```

Round Robin cycles through nodes in order using an atomic counter, which makes it deterministic and fair under uniform workloads.

Try selecting nodes multiple times:

```elixir
{:ok, node1} = RpcLoadBalancer.select_node(:round_robin_balancer)
{:ok, node2} = RpcLoadBalancer.select_node(:round_robin_balancer)
```

With a single node both will return the same value, but in a multi-node cluster you'll see them cycle through the available nodes.

Some algorithms take options through `:algorithm_opts` — for example `HashRing` routes by a `:key`, `WeightedRoundRobin` takes a `weights:` map, and `LeastCpu` takes polling settings. The how-to guides cover each one.

## Step 6: Bind the configuration to a module

Passing `load_balancer: :my_balancer` on every call gets repetitive. `use RpcLoadBalancer` defines a module that carries the configuration and exposes the same API with the balancer pre-filled:

```elixir
defmodule MyApp.LoadBalancer do
  use RpcLoadBalancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin
end
```

Start it and call through it:

```elixir
{:ok, _pid} = MyApp.LoadBalancer.start_link()

{:ok, result} = MyApp.LoadBalancer.call(node(), String, :reverse, ["hello"])
{:ok, selected} = MyApp.LoadBalancer.select_node()
{:ok, members} = MyApp.LoadBalancer.get_members()
```

The load balancer is registered under the module name (`MyApp.LoadBalancer`), so `RpcLoadBalancer.call(..., load_balancer: MyApp.LoadBalancer)` also works.

## Step 7: Add the balancer to your supervision tree

In a real application, start load balancers under your supervisor instead of calling `start_link` manually. **The load balancer should be the last child in the list.** OTP shuts down children in reverse start order, so placing it last means it shuts down first during deployment — the node deregisters from the `:pg` group before your application logic stops, preventing other nodes from routing calls to a node that is mid-shutdown.

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyApp.Repo,
      MyAppWeb.Endpoint,
      MyApp.LoadBalancer
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

Without a named module, use the tuple form instead:

```elixir
{RpcLoadBalancer,
 name: :my_balancer,
 selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin}
```

The balancer will start, register the current node in the `:pg` group, and begin monitoring for node joins and leaves. On shutdown, it leaves the group and performs graceful connection draining — waiting for in-flight calls to complete (up to 15 seconds by default, `:drain_timeout`) before the process terminates.

## What you've learned

- `RpcLoadBalancer.call/5` and `cast/5` wrap `:erpc` with structured error handling
- `RpcLoadBalancer.start_link/1` creates a named balancer backed by `:pg`
- Passing `load_balancer: :name` to `call/5` or `cast/5` routes through the balancer, retrying while the pool is empty
- `RpcLoadBalancer.select_node/2` selects a node without making an RPC call
- Selection algorithms are swappable via the `:selection_algorithm` option
- `use RpcLoadBalancer` binds a configuration to a module with its own API
- Balancers belong at the end of your application's supervision tree

## Next steps

- [Define a named load balancer module](../how-to/named-load-balancer-module.md)
- [How to write a custom selection algorithm](../how-to/custom-selection-algorithm.md)
- [How to use hash-based routing](../how-to/hash-based-routing.md)
- [Collect telemetry and metrics](../how-to/telemetry-and-metrics.md)
- [Testing with CallDirect](../how-to/testing-with-call-direct.md)
- [Architecture and design decisions](../explanation/architecture.md)
- [Full API reference](../reference/load_balancer.md)
