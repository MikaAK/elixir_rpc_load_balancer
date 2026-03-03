# How to Configure Weighted Round Robin

Use the Weighted Round Robin algorithm to distribute traffic proportionally based on node capacity.

## Start with weights

Pass a weight map via `algorithm_opts`. Keys are node atoms, values are positive integers representing relative capacity:

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :weighted_balancer,
    selection_algorithm: SelectionAlgorithm.WeightedRoundRobin,
    algorithm_opts: [weights: %{:"node1@host" => 3, :"node2@host" => 1}]
  )
```

In this configuration, `node1@host` receives roughly 3x the traffic of `node2@host`.

## Default weight

Nodes not present in the weight map receive a default weight of 1:

```elixir
algorithm_opts: [weights: %{:"high_capacity@host" => 5}]
```

Any other node joining the balancer will be treated as weight 1.

## How it works

The algorithm expands the node list by duplicating each node according to its weight, then cycles through the expanded list using an atomic ETS counter. For a weight map of `%{a: 3, b: 1}`, the expanded list is `[a, a, a, b]`, so `a` is selected 3 out of every 4 calls.

## Use in a supervision tree

```elixir
children = [
  {RpcLoadBalancer.LoadBalancer,
   name: :weighted_balancer,
   selection_algorithm: SelectionAlgorithm.WeightedRoundRobin,
   algorithm_opts: [
     weights: %{
       :"worker1@host" => 4,
       :"worker2@host" => 2,
       :"worker3@host" => 1
     }
   ]}
]
```

## Counter overflow

The internal counter resets when it exceeds 10,000,000 to prevent unbounded growth. This is handled automatically and does not affect selection correctness.
