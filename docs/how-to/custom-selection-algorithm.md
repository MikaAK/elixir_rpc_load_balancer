# How to Write a Custom Selection Algorithm

This guide shows you how to implement your own node selection algorithm by implementing the `RpcLoadBalancer.LoadBalancer.SelectionAlgorithm` behaviour.

## Implement the behaviour

Create a module that declares `@behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm` and implements the one required callback, `choose_from_nodes/3`:

```elixir
defmodule MyApp.PriorityAlgorithm do
  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  @impl true
  def choose_from_nodes(_load_balancer_name, node_list, opts \\ []) do
    priority_node = Keyword.get(opts, :priority_node)

    if priority_node && priority_node in node_list do
      priority_node
    else
      Enum.random(node_list)
    end
  end
end
```

`choose_from_nodes/3` receives the load balancer name, the current list of registered member nodes, and caller options. It is called on every selection from every calling process concurrently — keep it fast and lock-free.

The node list is never empty when your callback runs through `RpcLoadBalancer.select_node/2`; an empty `:pg` group returns `{:error, %ErrorMessage{code: :service_unavailable}}` before selection is attempted. The dispatch layer still forwards `[]` if you call `SelectionAlgorithm.choose_from_nodes/4` yourself, so raise (as `Enum.random/1` does) rather than returning a bogus node.

## Add optional lifecycle callbacks

All other callbacks are optional. The `SelectionAlgorithm` dispatch layer checks `function_exported?/3` before invoking them, so implement only what you need.

### `init/2`

Called once when the load balancer starts, before it joins the `:pg` group. Receives `algorithm_opts` from `start_link/1`. Use it to store configuration or seed state. Write-once config belongs in `:persistent_term`; the built-in algorithms namespace their keys by `{__MODULE__, load_balancer_name, key}`:

```elixir
@impl true
def init(load_balancer_name, opts) do
  :persistent_term.put({__MODULE__, load_balancer_name, :threshold}, Keyword.get(opts, :threshold, 10))
  :ok
end
```

For a per-balancer atomic counter, register a slot in the shared `CounterCache`:

```elixir
@counter_slot 7

@impl true
def init(load_balancer_name, _opts) do
  RpcLoadBalancer.LoadBalancer.CounterCache.register(load_balancer_name, @counter_slot)
  :ok
end
```

Slot ids are namespaced per algorithm and per balancer — `RoundRobin` uses `1`, `WeightedRoundRobin` uses `2`; pick anything that doesn't collide within your own algorithm.

### `on_node_change/2`

Called when nodes join or leave the `:pg` group. Use it to invalidate derived data or drop per-node state:

```elixir
@impl true
def on_node_change(load_balancer_name, {:joined, nodes}) do
  Enum.each(nodes, &setup_node_state(load_balancer_name, &1))
  :ok
end

def on_node_change(load_balancer_name, {:left, nodes}) do
  Enum.each(nodes, &cleanup_node_state(load_balancer_name, &1))
  :ok
end
```

### `release_node/2`

Called after a load-balanced `call/5` or `cast/5` finishes (success or failure). Connection-tracking algorithms use this to decrement counters:

```elixir
@impl true
def release_node(load_balancer_name, node) do
  RpcLoadBalancer.LoadBalancer.CounterCache.decrement_node(load_balancer_name, node)
  :ok
end
```

### `choose_nodes/4`

Pick `count` distinct nodes for a key — used for replica placement. Without it, `SelectionAlgorithm.choose_nodes/5` falls back to `Enum.shuffle/1 |> Enum.take(count)`:

```elixir
@impl true
def choose_nodes(_load_balancer_name, node_list, count, _opts) do
  Enum.take(node_list, count)
end
```

### `local?/0`

Return `true` to make the balancer skip `:erpc` entirely and run `apply/3` (calls) or `spawn/3` (casts) on the local node. This is how `CallDirect` works. Selection is never invoked when `local?/0` is true.

### `child_specs/2`

Return supervisor child specs the algorithm needs per balancer — for example a background poller. They start under the balancer's supervisor **before** the `LoadBalancer` GenServer, so they exist by the time `select_node/2` can be called. Receives `algorithm_opts`:

```elixir
@impl true
def child_specs(load_balancer_name, opts) do
  poller_opts = Keyword.put(opts, :load_balancer_name, load_balancer_name)

  [
    Supervisor.child_spec({MyApp.MetricPoller, poller_opts},
      id: :"#{load_balancer_name}_metric_poller"
    )
  ]
end
```

`LeastCpu` uses this to start its CPU `Poller`.

### `caches/0`

Return the `elixir_cache` modules your algorithm depends on. The application supervisor starts the caches for the built-in algorithms at boot; **it does not know about your algorithm**, so declaring `caches/0` on a custom algorithm is informational only. Start your cache yourself — either from `child_specs/2` or in your own application's supervision tree:

```elixir
children = [
  {Cache, [MyApp.MyAlgorithmCache]},
  MyApp.LoadBalancer
]
```

## Use your algorithm

Pass it as the `:selection_algorithm` option when starting a load balancer:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :priority_balancer,
    selection_algorithm: MyApp.PriorityAlgorithm,
    algorithm_opts: [threshold: 20]
  )
```

The `algorithm_opts` keyword list is forwarded to `init/2` and `child_specs/2`.

## Pass per-call options

`select_node/2` forwards **all** its options to `choose_from_nodes/3`:

```elixir
{:ok, node} =
  RpcLoadBalancer.select_node(:priority_balancer, priority_node: :"preferred@host")
```

`call/5` and `cast/5` forward only `:key`, `:call_directly?`, and `:load_balancer` to the algorithm — other keys are consumed by the RPC layer (`:timeout`, `:retry?`, ...) or dropped. If your algorithm needs caller input on the RPC path, read it from the `:key` option:

```elixir
RpcLoadBalancer.call(node(), Mod, :fun, [arg],
  load_balancer: :priority_balancer,
  key: :"preferred@host"
)
```

## Telemetry

You get selection telemetry for free: the dispatch layer emits `[:rpc_load_balancer, :node_selected]` after every successful `choose_from_nodes/3` with your module in the `:algorithm` metadata. See [Collect Telemetry and Metrics](telemetry-and-metrics.md).

## Reference implementations

The built-in algorithms are short and cover every callback:

- `Random` — the minimum viable algorithm (one callback)
- `RoundRobin` — `init/2` + shared atomic counter
- `LeastConnections` / `PowerOfTwo` — `release_node/2` and `on_node_change/2` with per-node counters
- `HashRing` — `choose_nodes/4`, `caches/0`, `:persistent_term` config + ETS-cached derived data
- `LeastCpu` — `child_specs/2` with a background poller
- `CallDirect` — `local?/0`
