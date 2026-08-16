# How to Define a Named Load Balancer Module

`use RpcLoadBalancer` defines a module that carries a fixed load balancer configuration and exposes the `RpcLoadBalancer` API with the `:load_balancer` option pre-filled. Use it when your application has one (or a few) well-known balancers and you don't want to thread `load_balancer: :name` through every call site.

## Define the module

Pass the same options you would pass to `RpcLoadBalancer.start_link/1`, minus `:name` — the module itself becomes the name:

```elixir
defmodule MyApp.LoadBalancer do
  use RpcLoadBalancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing,
    algorithm_opts: [weight: 256],
    node_match_list: ["my_app"],
    drain_timeout: :timer.seconds(30)
end
```

## Supervise it

The module defines `child_spec/1`, so it drops straight into a supervision tree. Keep it last so it shuts down first and drains before the rest of your app stops:

```elixir
children = [
  MyApp.Repo,
  MyAppWeb.Endpoint,
  MyApp.LoadBalancer
]
```

`start_link/1` and `child_spec/1` accept a keyword list of runtime overrides that are merged over the `use` options:

```elixir
children = [
  {MyApp.LoadBalancer, algorithm_opts: [weight: 512]}
]
```

## Call through it

Every function has the same shape as its `RpcLoadBalancer` counterpart with `load_balancer: MyApp.LoadBalancer` set for you:

```elixir
{:ok, result} = MyApp.LoadBalancer.call(node(), MyModule, :fun, [arg], key: user_id)
:ok = MyApp.LoadBalancer.cast(node(), MyModule, :fun, [arg])

{:ok, node} = MyApp.LoadBalancer.select_node(key: user_id)
{:ok, nodes} = MyApp.LoadBalancer.get_members()

{:ok, result} = MyApp.LoadBalancer.call_on_random_node("worker", MyModule, :fun, [arg])
:ok = MyApp.LoadBalancer.cast_on_random_node("worker", MyModule, :fun, [arg])
```

The generated functions:

| Function | Delegates to |
|---|---|
| `child_spec/1` | `%{id: __MODULE__, start: {__MODULE__, :start_link, [overrides]}}` |
| `start_link/1` | `RpcLoadBalancer.start_link(use_opts ++ [name: __MODULE__] ++ overrides)` |
| `get_members/0` | `RpcLoadBalancer.get_members(__MODULE__)` |
| `select_node/1` | `RpcLoadBalancer.select_node(__MODULE__, opts)` |
| `call/5` | `RpcLoadBalancer.call(node, m, f, a, opts ++ [load_balancer: __MODULE__])` |
| `cast/5` | `RpcLoadBalancer.cast(node, m, f, a, opts ++ [load_balancer: __MODULE__])` |
| `call_on_random_node/5` | `RpcLoadBalancer.call_on_random_node(filter, m, f, a, opts ++ [load_balancer: __MODULE__])` |
| `cast_on_random_node/5` | `RpcLoadBalancer.cast_on_random_node(filter, m, f, a, opts ++ [load_balancer: __MODULE__])` |

For `call_on_random_node/5` and `cast_on_random_node/5`, the `:load_balancer` option only enrols the call in this balancer's connection draining — node selection still comes from the filter, not the algorithm.

## Interoperate with the plain API

The balancer is registered under the module name, so the plain API works too:

```elixir
RpcLoadBalancer.call(node(), MyModule, :fun, [arg], load_balancer: MyApp.LoadBalancer)
RpcLoadBalancer.select_node(MyApp.LoadBalancer, key: user_id)
```

## Switch algorithms per environment

Combine with a compile-time attribute to run `CallDirect` in tests:

```elixir
defmodule MyApp.LoadBalancer do
  @algorithm if Mix.env() === :test,
               do: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirect,
               else: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin

  use RpcLoadBalancer, selection_algorithm: @algorithm
end
```

See [Testing with CallDirect](testing-with-call-direct.md) for more.
