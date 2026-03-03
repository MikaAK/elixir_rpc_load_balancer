# How to Write a Custom Selection Algorithm

This guide shows you how to implement your own node selection algorithm by implementing the `SelectionAlgorithm` behaviour.

## Implement the behaviour

Create a module that uses `@behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm` and implements the required `choose_from_nodes/3` callback:

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

`choose_from_nodes/3` receives the load balancer name, the current list of available nodes, and any options passed through from `select_node/2` or `call/5`.

## Add optional lifecycle callbacks

The behaviour defines three optional callbacks for algorithms that need to manage state:

### `init/2`

Called once when the load balancer starts. Use this to set up ETS entries or other state:

```elixir
@impl true
def init(load_balancer_name, opts) do
  initial_value = Keyword.get(opts, :initial, 0)
  RpcLoadBalancer.LoadBalancer.CounterCache.insert_new({{:my_counter, load_balancer_name}, initial_value})
  :ok
end
```

### `on_node_change/2`

Called when nodes join or leave the `:pg` group:

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

Called after an RPC call completes when using the convenience `LoadBalancer.call/5` API. Connection-tracking algorithms use this to decrement counters:

```elixir
@impl true
def release_node(load_balancer_name, node) do
  decrement_my_counter(load_balancer_name, node)
  :ok
end
```

## Use your algorithm

Pass it as the `:selection_algorithm` option when starting a load balancer:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :priority_balancer,
    selection_algorithm: MyApp.PriorityAlgorithm
  )
```

Pass custom options through `select_node/2` or `call/5`:

```elixir
{:ok, node} =
  RpcLoadBalancer.LoadBalancer.select_node(:priority_balancer, priority_node: :"preferred@host")
```

## Use algorithm_opts for initialization

If your algorithm needs configuration at startup, pass it via `:algorithm_opts`:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :custom_balancer,
    selection_algorithm: MyApp.PriorityAlgorithm,
    algorithm_opts: [initial: 100]
  )
```

The `algorithm_opts` keyword list is forwarded to your `init/2` callback.
