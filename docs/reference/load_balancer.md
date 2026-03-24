# Load Balancer Reference

Complete API reference for all public modules in `rpc_load_balancer`.

## RpcLoadBalancer

Top-level module and per-instance Supervisor. Provides the public API for node selection, RPC calls/casts, random-node helpers, and low-level `:erpc` wrappers.

### Types

```elixir
@type name :: atom()
```

### Functions

#### `start_link(opts)`

Starts a load balancer Supervisor that manages the caches and GenServer for a single balancer instance.

**Options:**
- `:name` (required) — registered name for the balancer
- `:selection_algorithm` — module implementing `SelectionAlgorithm` (default: `SelectionAlgorithm.Random`)
- `:algorithm_opts` — keyword list forwarded to the algorithm's `init/2` callback (default: `[]`)
- `:node_match_list` — controls which nodes join the `:pg` group (default: `:all`)
  - `:all` — every node joins
  - `[String.t() | Regex.t()]` — only nodes matching at least one entry join
- `:drain_timeout` — maximum time in milliseconds to wait for in-flight calls to complete during shutdown (default: `15_000`)

**Returns:** `Supervisor.on_start()`

#### `get_members(load_balancer_name)`

Returns the deduplicated list of nodes registered in the `:pg` group for this balancer.

**Returns:**
- `{:ok, [node()]}` when members exist
- `{:error, %ErrorMessage{code: :service_unavailable}}` when the group is empty

#### `select_node(load_balancer_name, opts \\ [])`

Selects a node from the balancer's registered members using the configured algorithm.

**Options:** forwarded to the algorithm's `choose_from_nodes/3` (e.g., `key: "user:123"` for HashRing)

**Returns:**
- `{:ok, node()}` on success
- `{:error, %ErrorMessage{code: :service_unavailable}}` when no nodes are registered

#### `call(node, module, fun, args, opts \\ [])`

Executes a synchronous RPC call. When the `:load_balancer` option is present, the call is routed through the named balancer (the `node` argument is ignored). Otherwise, the call goes directly to the specified node via `:erpc.call/5`.

**Options:**
- `:timeout` — call timeout in milliseconds (default: `10_000`)
- `:load_balancer` — name of a running load balancer to route through
- `:key` — forwarded to the selection algorithm (used by HashRing)
- `:call_directly?` — when `true`, executes locally via `apply/3` regardless of balancer (default: from config)

**Returns:**
- `{:ok, result}` on success
- `{:error, %ErrorMessage{code: :request_timeout}}` on timeout
- `{:error, %ErrorMessage{code: :service_unavailable}}` on connection failure or no members
- `{:error, %ErrorMessage{code: :bad_request}}` on bad arguments

#### `cast(node, module, fun, args, opts \\ [])`

Executes an asynchronous RPC cast. When the `:load_balancer` option is present, the cast is routed through the named balancer (the `node` argument is ignored). Otherwise, the cast goes directly to the specified node via `:erpc.cast/4`.

**Options:**
- `:load_balancer` — name of a running load balancer to route through
- `:key` — forwarded to the selection algorithm (used by HashRing)
- `:call_directly?` — when `true`, executes locally via `spawn/3` regardless of balancer (default: from config)

**Returns:**
- `:ok` on success
- `{:error, %ErrorMessage{}}` on failure

#### `call_on_random_node(node_filter, module, fun, args, opts \\ [])`

Selects a random node from `Node.list/0` whose name contains `node_filter` (substring match), then executes an RPC call on it. If the current node matches the filter or `:call_directly?` is `true`, executes locally.

Retries automatically when no matching nodes are found (configurable via `:retry?`, `:retry_count`, `:retry_sleep`).

**Options:**
- `:timeout` — call timeout in milliseconds
- `:load_balancer` — optional balancer name for connection draining
- `:call_directly?` — execute locally (default: from config)
- `:retry?` — enable retry on no nodes (default: from config, `true`)
- `:retry_count` — max retries (default: from config, `5`)
- `:retry_sleep` — sleep between retries in milliseconds (default: `5_000`)

**Returns:**
- `{:ok, result}` on success
- `{:error, %ErrorMessage{code: :service_unavailable}}` when no nodes match

#### `cast_on_random_node(node_filter, module, fun, args, opts \\ [])`

Same as `call_on_random_node/5` but uses `cast/5` instead of `call/5`.

**Returns:**
- `:ok` on success
- `{:error, %ErrorMessage{code: :service_unavailable}}` when no nodes match

---

## RpcLoadBalancer.Config

Configuration defaults. All values can be overridden via application config:

```elixir
config :rpc_load_balancer,
  call_directly?: false,
  retry?: true,
  retry_count: 5
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `:call_directly?` | `boolean()` | `false` | When `true`, all load-balanced calls execute locally via `apply/3` |
| `:retry?` | `boolean()` | `true` | Enable automatic retry when no nodes are available |
| `:retry_count` | `non_neg_integer()` | `5` | Maximum number of retries |

---

## RpcLoadBalancer.LoadBalancer

GenServer that joins the `:pg` group, monitors membership changes, and performs graceful connection draining on shutdown. Started internally by `RpcLoadBalancer.start_link/1` — you don't typically interact with this module directly.

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

Called to pick multiple distinct nodes. Used internally by the `SelectionAlgorithm` dispatch layer. Algorithms that don't implement this fall back to returning randomly shuffled nodes.

```elixir
@callback on_node_change(load_balancer_name(), {:joined | :left, [node()]}) :: :ok
```

Called when the `:pg` group membership changes.

```elixir
@callback release_node(load_balancer_name(), node()) :: :ok
```

Called after an RPC call completes to clean up per-node state (e.g., decrement connection counters).

```elixir
@callback local?() :: boolean()
```

When `true`, the load balancer bypasses `:erpc` and executes calls locally via `apply/3` and casts via `spawn/3`. Used by `CallDirect`.

---

## Built-in Algorithms

All algorithms live under `RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.*`.

### Random

Picks a random node using `Enum.random/1`. No state, no configuration.

### RoundRobin

Cycles through nodes using an atomic counter (`CounterCache`). The counter auto-resets after 10,000,000 to prevent overflow.

### LeastConnections

Tracks active connections per node with atomic counters. Always picks the node with the lowest count. Increments on selection, decrements on `release_node/2`.

Implements: `init/2`, `choose_from_nodes/3`, `on_node_change/2`, `release_node/2`

### PowerOfTwo

Samples two random nodes and picks the one with fewer active connections. Same counter infrastructure as LeastConnections but with O(1) selection cost instead of O(n).

Implements: `init/2`, `choose_from_nodes/3`, `on_node_change/2`, `release_node/2`

### HashRing

Consistent hash ring powered by [`libring`](https://hex.pm/packages/libring). Each physical node is sharded into `weight` points (default: 128) distributed across a `2^32` continuum using SHA-256. Key lookup finds the next highest shard on the ring via `gb_tree`. Falls back to random selection when no key is given. The ring is stored in a `PersistentTerm`-backed cache and lazily rebuilt when topology changes.

Supports replica selection via `choose_nodes/4` using `HashRing.key_to_nodes/3` — returns multiple distinct nodes for a given key, walking the ring from the primary shard.

**Algorithm options:**
- `:weight` — number of shards per physical node (default: `128`)

Implements: `init/2`, `choose_from_nodes/3`, `choose_nodes/4`, `on_node_change/2`

### WeightedRoundRobin

Expands the node list by duplicating each node according to its weight, then cycles through with an atomic counter. Weights are passed via `algorithm_opts: [weights: %{node => integer}]`. Nodes without an explicit weight default to 1.

Implements: `init/2`, `choose_from_nodes/3`

### CallDirect

Executes calls directly on the local node via `apply/3` instead of going through `:erpc`. `call/5` with `load_balancer:` returns `{:ok, apply(module, fun, args)}` and `cast/5` with `load_balancer:` uses `spawn/3` and returns `:ok`. No remote nodes are contacted.

Designed for testing and single-node deployments where RPC overhead is unnecessary. Should always be used as the selection algorithm in test environments.

Implements: `local?/0`, `choose_from_nodes/3`

---

## RpcLoadBalancer.Retry

Retry logic for RPC operations that may fail when no nodes are available. Used internally by `call_on_random_node/5` and `cast_on_random_node/5`.

#### `with_retry(opts \\ [], fun)`

Calls `fun` repeatedly when it returns `:retry`, up to `:retry_count` times with `:retry_sleep` between attempts.

**Options:**
- `:retry?` — enable retrying (default: from config)
- `:retry_count` — max retries (default: from config)
- `:retry_sleep` — sleep between retries in milliseconds (default: `5_000`)

---

## RpcLoadBalancer.LoadBalancer.Drainer

Tracks in-flight RPC calls and provides graceful connection draining. Uses atomic counters to track the number of active calls per load balancer. During shutdown, the GenServer leaves its `:pg` group and calls `drain/2` to wait for existing calls to complete before the process terminates.

#### `track_call(load_balancer_name)`

Increments the in-flight counter.

#### `release_call(load_balancer_name)`

Decrements the in-flight counter.

#### `in_flight_count(load_balancer_name)`

Returns the current number of in-flight calls.

#### `drain(load_balancer_name, timeout \\ 15_000)`

Blocks until all in-flight calls complete or the timeout expires. Returns `:ok` or `{:error, :timeout}`.

---

## Internal Modules

These modules are not part of the public API but are documented here for contributors.

### `RpcLoadBalancer.LoadBalancer.Pg`

Starts and wraps the `:pg` scope (`:rpc_load_balancer`). Started as a child of the application supervisor.

### `RpcLoadBalancer.LoadBalancer.AlgorithmCache`

`PersistentTerm`-backed cache (via `elixir_cache`) that maps `load_balancer_name -> algorithm_module`.

### `RpcLoadBalancer.LoadBalancer.ValueCache`

`PersistentTerm`-backed cache (via `elixir_cache`) used for general-purpose storage (hash ring data, weight maps).

### `RpcLoadBalancer.LoadBalancer.CounterCache`

Atomic counter cache (via `elixir_cache` `Cache.Counter`) used for round robin indices and per-node connection counts.

### `RpcLoadBalancer.LoadBalancer.DrainerCache`

Atomic counter cache (via `elixir_cache` `Cache.Counter`) used for tracking in-flight calls per load balancer.
