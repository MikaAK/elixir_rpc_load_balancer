# How to Configure Weighted Round Robin

Use the `WeightedRoundRobin` algorithm to distribute traffic proportionally based on node capacity.

## Start with weights

Pass a weight map via `algorithm_opts`. Keys are node atoms, values are positive integers representing relative capacity:

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, _pid} =
  RpcLoadBalancer.start_link(
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

At `init/2` the weight map is stored in `:persistent_term` (it is written once and never changes). On selection the algorithm:

1. Looks up the **expanded node list** for the current member list in `WeightedRoundRobinCache` (ETS). The expanded list duplicates each node according to its weight — for `%{a: 3, b: 1}` it is `[a, a, a, b]`. It is built lazily on the first selection after a membership change and cached, keyed by the exact member list.
2. Increments a shared atomic counter and takes `rem(count, length(expanded))` as the index.

Steady state is one ETS lookup, one atomic increment, and one `Enum.at/2` — about 0.9 μs, independent of cluster size. Membership changes invalidate the cached list via `on_node_change/2`.

## Weights are fixed at startup

Because the weight map lives in `:persistent_term`, changing it requires restarting the balancer (e.g. `Supervisor.terminate_child/2` + `restart_child/2`, or a rolling deploy). Nodes that are in the map but not currently connected simply don't appear in the expanded list; they pick up their weight when they join.

## Use in a supervision tree

```elixir
children = [
  {RpcLoadBalancer,
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

Or as a named module:

```elixir
defmodule MyApp.WeightedBalancer do
  use RpcLoadBalancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobin,
    algorithm_opts: [weights: %{:"worker1@host" => 4, :"worker2@host" => 2}]
end
```

## Counter overflow

The internal counter resets when it exceeds 10,000,000 to prevent unbounded growth. This is handled automatically; the reset causes at most one out-of-sequence pick and does not affect selection correctness.
