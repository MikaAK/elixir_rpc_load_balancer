# Tutorial: Getting Started with RpcLoadBalancer

This tutorial walks you through setting up `rpc_load_balancer` from scratch. By the end, you will have a working load balancer distributing RPC calls across BEAM nodes.

## What you'll build

A small Elixir application that:

1. Makes direct RPC calls to remote nodes
2. Runs a load balancer that automatically selects nodes
3. Uses a selection algorithm to control how nodes are picked

## Prerequisites

- Elixir 1.13+
- A Mix project

## Step 1: Add the dependency

Open your `mix.exs` and add `rpc_load_balancer`:

```elixir
def deps do
  [
    {:rpc_load_balancer, "~> 0.1.0"}
  ]
end
```

Fetch the dependency:

```bash
mix deps.get
```

The application starts automatically. It boots a `:pg` process group and two ETS caches that the load balancer needs.

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

The `call/5` function wraps `:erpc.call/5` and returns `{:ok, result}` on success or `{:error, %ErrorMessage{}}` on failure. The default timeout is 10 seconds; override it with the `:timeout` option:

```elixir
{:ok, result} = RpcLoadBalancer.call(node(), String, :upcase, ["hello"], timeout: :timer.seconds(5))
```

For fire-and-forget calls, use `cast/4`:

```elixir
:ok = RpcLoadBalancer.cast(node(), IO, :puts, ["hello from cast"])
```

## Step 3: Start a load balancer

Now start a load balancer instance. Each balancer is a GenServer that registers the current node in a `:pg` group:

```elixir
{:ok, _pid} = RpcLoadBalancer.LoadBalancer.start_link(name: :my_balancer)
```

The balancer uses the `Random` algorithm by default. Verify it's running by selecting a node:

```elixir
{:ok, selected} = RpcLoadBalancer.LoadBalancer.select_node(:my_balancer)
```

Since you're running a single node, `selected` will be your current node.

## Step 4: Use the convenience API

Instead of selecting a node and making the RPC call separately, combine both in one step:

```elixir
{:ok, result} =
  RpcLoadBalancer.LoadBalancer.call(:my_balancer, String, :reverse, ["hello"])
```

This selects a node using the configured algorithm, executes the RPC call on that node, and returns the result. There's also a `cast/5` variant:

```elixir
:ok = RpcLoadBalancer.LoadBalancer.cast(:my_balancer, IO, :puts, ["load balanced cast"])
```

## Step 5: Choose a selection algorithm

Start a second load balancer with Round Robin:

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :round_robin_balancer,
    selection_algorithm: SelectionAlgorithm.RoundRobin
  )
```

Round Robin cycles through nodes in order using an atomic ETS counter, which makes it deterministic and fair under uniform workloads.

Try selecting nodes multiple times:

```elixir
{:ok, node1} = RpcLoadBalancer.LoadBalancer.select_node(:round_robin_balancer)
{:ok, node2} = RpcLoadBalancer.LoadBalancer.select_node(:round_robin_balancer)
```

With a single node both will return the same value, but in a multi-node cluster you'll see them cycle through the available nodes.

## Step 6: Add the balancer to your supervision tree

In a real application, start load balancers under your supervisor instead of calling `start_link` manually:

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {RpcLoadBalancer.LoadBalancer,
       name: :my_balancer,
       selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

The balancer will start, register the current node in the `:pg` group, and begin monitoring for node joins and leaves.

## What you've learned

- `RpcLoadBalancer.call/5` and `cast/4` wrap `:erpc` with structured error handling
- `LoadBalancer.start_link/1` creates a named balancer backed by `:pg`
- `LoadBalancer.call/5` and `cast/5` combine node selection with RPC execution
- Selection algorithms are swappable via the `:selection_algorithm` option
- Balancers belong in your application's supervision tree

## Next steps

- [How to write a custom selection algorithm](../how-to/custom-selection-algorithm.md)
- [How to use hash-based routing](../how-to/hash-based-routing.md)
- [Architecture and design decisions](../explanation/architecture.md)
- [Full API reference](../reference/load_balancer.md)
