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

The application starts automatically. It boots a `:pg` process group and the caches that load balancers need.

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

For fire-and-forget calls, use `cast/5`:

```elixir
:ok = RpcLoadBalancer.cast(node(), IO, :puts, ["hello from cast"])
```

## Step 3: Start a load balancer

Now start a load balancer instance. `RpcLoadBalancer.start_link/1` starts a Supervisor that manages the caches and GenServer for a single balancer. The GenServer registers the current node in a `:pg` group:

```elixir
{:ok, _pid} = RpcLoadBalancer.start_link(name: :my_balancer)
```

The balancer uses the `Random` algorithm by default. Verify it's running by selecting a node:

```elixir
{:ok, selected} = RpcLoadBalancer.select_node(:my_balancer)
```

Since you're running a single node, `selected` will be your current node.

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

## Step 6: Add the balancer to your supervision tree

In a real application, start load balancers under your supervisor instead of calling `start_link` manually. **The load balancer should be the last child in the list.** OTP shuts down children in reverse start order, so placing it last means it shuts down first during deployment — the node deregisters from the `:pg` group before your application logic stops, preventing other nodes from routing calls to a node that is mid-shutdown.

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyApp.Repo,
      MyAppWeb.Endpoint,
      {RpcLoadBalancer,
       name: :my_balancer,
       selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

The balancer will start, register the current node in the `:pg` group, and begin monitoring for node joins and leaves. On shutdown, it performs graceful connection draining — waiting for in-flight calls to complete (up to 15 seconds by default) before the process terminates. This ensures the node deregisters from the `:pg` group and finishes ongoing work before the rest of the application tears down.

## What you've learned

- `RpcLoadBalancer.call/5` and `cast/5` wrap `:erpc` with structured error handling
- `RpcLoadBalancer.start_link/1` creates a named balancer backed by `:pg`
- Passing `load_balancer: :name` to `call/5` or `cast/5` routes through the balancer
- `RpcLoadBalancer.select_node/2` selects a node without making an RPC call
- Selection algorithms are swappable via the `:selection_algorithm` option
- Balancers belong in your application's supervision tree

## Next steps

- [How to write a custom selection algorithm](../how-to/custom-selection-algorithm.md)
- [How to use hash-based routing](../how-to/hash-based-routing.md)
- [Architecture and design decisions](../explanation/architecture.md)
- [Full API reference](../reference/load_balancer.md)
