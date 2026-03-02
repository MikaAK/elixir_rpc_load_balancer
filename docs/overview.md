# rpc_load_balancer

`rpc_load_balancer` provides RPC wrappers and a distributed node load balancer.

## Key Features

- RPC wrappers around `:erpc.call/5` and `:erpc.cast/4`
- A load balancer that registers available nodes using `:pg`
- Pluggable selection algorithms (random, round robin, least connections, power of two, hash ring, weighted round robin)

## Installation

Add `rpc_load_balancer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rpc_load_balancer, "~> 0.1.0"}
  ]
end
```

## Basic usage

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

```elixir
{:ok, _pid} = RpcLoadBalancer.LoadBalancer.start_link(name: :my_balancer)

{:ok, node} = RpcLoadBalancer.LoadBalancer.select_node(:my_balancer)
```
