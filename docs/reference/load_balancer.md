# Load Balancer Reference

Complete API reference for all public modules in `rpc_load_balancer`.

## RpcLoadBalancer

Top-level module providing RPC wrappers around `:erpc`.

### Types

```elixir
@spec call(node(), module(), atom(), [any()], timeout: timeout()) :: ErrorMessage.t_res(any())
@spec cast(node(), module(), atom(), [term()]) :: :ok | {:error, ErrorMessage.t()}
```

### Functions

#### `call(node, module, fun, args, opts \\ [timeout: :timer.seconds(10)])`

Executes a synchronous RPC call on the given node. Wraps `:erpc.call/5`.

**Returns:**
- `{:ok, result}` on success
- `{:error, %ErrorMessage{code: :request_timeout}}` on timeout
- `{:error, %ErrorMessage{code: :service_unavailable}}` on connection failure
- `{:error, %ErrorMessage{code: :bad_request}}` on bad arguments

**Options:**
- `:timeout` — call timeout in milliseconds (default: `10_000`)

#### `cast(node, module, fun, args)`

Executes an asynchronous RPC cast on the given node. Wraps `:erpc.cast/4`.

**Returns:**
- `:ok` on success
- `{:error, %ErrorMessage{}}` on failure

---

## RpcLoadBalancer.LoadBalancer

GenServer-based load balancer that registers nodes via `:pg` and selects them using a pluggable algorithm.

### Types

```elixir
@type name :: atom() | module()
@type node_match_list :: [String.t() | Regex.t()] | :all
@type option ::
        {:node_match_list, node_match_list()}
        | {:selection_algorithm, module()}
        | {:algorithm_opts, keyword()}
@type opts :: [GenServer.option() | option()]
```

### Functions

#### `start_link(opts \\ [])`

Starts a load balancer GenServer.

**Options:**
- `:name` — registered name for the balancer (auto-generated if omitted)
- `:selection_algorithm` — module implementing `SelectionAlgorithm` (default: `SelectionAlgorithm.Random`)
- `:algorithm_opts` — keyword list forwarded to the algorithm's `init/2` callback (default: `[]`)
- `:node_match_list` — controls which nodes join the `:pg` group (default: `:all`)
  - `:all` — every node joins
  - `[String.t() | Regex.t()]` — only nodes matching at least one entry join

**Returns:** `GenServer.on_start()`

#### `select_node(load_balancer_name, opts \\ [])`

Selects a node from the balancer's registered members using the configured algorithm.

**Options:** forwarded to the algorithm's `choose_from_nodes/3` (e.g., `key: "user:123"` for HashRing)

**Returns:**
- `{:ok, node()}` on success
- `{:error, %ErrorMessage{code: :service_unavailable}}` when no nodes are registered

#### `release_node(load_balancer_name, node)`

Decrements the connection counter for the given node. Only meaningful for connection-tracking algorithms (LeastConnections, PowerOfTwo). No-op for other algorithms.

**Returns:** `:ok`

#### `call(load_balancer_name, module, fun, args, opts \\ [])`

Selects a node, executes a synchronous RPC call, then releases the node.

**Options:**
- `:key` — forwarded to the selection algorithm (used by HashRing)
- `:timeout` — forwarded to `RpcLoadBalancer.call/5`

**Returns:** `ErrorMessage.t_res(any())`

#### `cast(load_balancer_name, module, fun, args, opts \\ [])`

Selects a node and executes an asynchronous RPC cast.

**Options:**
- `:key` — forwarded to the selection algorithm

**Returns:** `:ok | {:error, ErrorMessage.t()}`

#### `select_nodes(load_balancer_name, count, opts \\ [])`

Selects multiple nodes from the balancer's registered members. Algorithms that implement `choose_nodes/4` (e.g., HashRing) provide consistent multi-node selection. Others fall back to randomly shuffled nodes.

**Options:** forwarded to the algorithm's `choose_nodes/4` (e.g., `key: "user:123"` for HashRing)

**Returns:**
- `{:ok, [node()]}` — up to `count` distinct nodes
- `{:error, %ErrorMessage{code: :service_unavailable}}` when no nodes are registered

#### `get_members(load_balancer_name)`

Returns the deduplicated list of nodes registered in the `:pg` group for this balancer.

**Returns:**
- `{:ok, [node()]}` when members exist
- `{:error, %ErrorMessage{code: :service_unavailable}}` when the group is empty

#### `pg_group_name()`

Returns the `:pg` scope atom used by all load balancers: `:rpc_load_balancer`.

---

## RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

Behaviour definition and dispatch layer for selection algorithms.

### Callbacks

#### Required

```elixir
@callback choose_from_nodes(load_balancer_name(), [node()], opts :: keyword()) :: node()
```

Called to pick one node from the available list. Receives the balancer name, the current node list, and any caller-provided options.

#### Optional

```elixir
@callback init(load_balancer_name(), opts :: keyword()) :: :ok
```

Called once during balancer startup. Receives `algorithm_opts` from `start_link/1`.

```elixir
@callback choose_nodes(load_balancer_name(), [node()], pos_integer(), opts :: keyword()) :: [node()]
```

Called by `LoadBalancer.select_nodes/3` to pick multiple distinct nodes for a given key. Used for replica selection. Algorithms that don't implement this fall back to returning randomly shuffled nodes.

```elixir
@callback on_node_change(load_balancer_name(), {:joined | :left, [node()]}) :: :ok
```

Called when the `:pg` group membership changes.

```elixir
@callback release_node(load_balancer_name(), node()) :: :ok
```

Called after an RPC call completes to clean up per-node state.

---

## Built-in Algorithms

All algorithms live under `RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.*`.

### Random

Picks a random node using `Enum.random/1`. No state, no configuration.

### RoundRobin

Cycles through nodes using an atomic ETS counter (`CounterCache`). The counter auto-resets after 10,000,000 to prevent overflow.

### LeastConnections

Tracks active connections per node with ETS counters. Always picks the node with the lowest count. Increments on selection, decrements on `release_node/2`.

Implements: `init/2`, `choose_from_nodes/3`, `on_node_change/2`, `release_node/2`

### PowerOfTwo

Samples two random nodes and picks the one with fewer active connections. Same counter infrastructure as LeastConnections but with O(1) selection cost instead of O(n).

Implements: `init/2`, `choose_from_nodes/3`, `on_node_change/2`, `release_node/2`

### HashRing

Consistent hash ring powered by [`libring`](https://hex.pm/packages/libring). Each physical node is sharded into `weight` points (default: 128) distributed across a `2^32` continuum using SHA-256. Key lookup finds the next highest shard on the ring via `gb_tree`. Falls back to random selection when no key is given. The ring is stored in ETS and lazily rebuilt when topology changes.

Supports replica selection via `choose_nodes/4` using `HashRing.key_to_nodes/3` — returns multiple distinct nodes for a given key, walking the ring from the primary shard.

**Algorithm options:**
- `:weight` — number of shards per physical node (default: `128`)

Implements: `init/2`, `choose_from_nodes/3`, `choose_nodes/4`, `on_node_change/2`

### WeightedRoundRobin

Expands the node list by duplicating each node according to its weight, then cycles through with an atomic counter. Weights are passed via `algorithm_opts: [weights: %{node => integer}]`. Nodes without an explicit weight default to 1.

Implements: `init/2`, `choose_from_nodes/3`

---

## Internal Modules

These modules are not part of the public API but are documented here for contributors.

### `RpcLoadBalancer.LoadBalancer.Pg`

Starts and wraps the `:pg` scope (`:rpc_load_balancer`). Started as a child of the application supervisor.

### `RpcLoadBalancer.LoadBalancer.AlgorithmCache`

ETS cache (via `elixir_cache`) that maps `load_balancer_name -> algorithm_module`. Configured with `read_concurrency: true` and `write_concurrency: true`.

### `RpcLoadBalancer.LoadBalancer.CounterCache`

ETS cache (via `elixir_cache`) used for atomic counters (round robin indices, connection counts) and weight storage. Configured with `read_concurrency: true` and `write_concurrency: true`.
