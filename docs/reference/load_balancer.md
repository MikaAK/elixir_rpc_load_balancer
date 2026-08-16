# Load Balancer Reference

Complete API reference for all public modules in `rpc_load_balancer`. Module-level docs (`h RpcLoadBalancer` in IEx) carry the same information; this page collects it in one place.

## RpcLoadBalancer

Top-level module. It is three things at once:

- the **public API** for RPC calls/casts, node selection, and random-node helpers
- a **per-instance Supervisor** (`start_link/1`) for one load balancer
- a **`use` macro** that generates a named load balancer module

### Types

```elixir
@type name :: atom()
```

A load balancer name is any atom, including a module name.

### `use RpcLoadBalancer`

```elixir
defmodule MyApp.LoadBalancer do
  use RpcLoadBalancer,
    selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing,
    node_match_list: ["my_app"]
end
```

Accepts every `start_link/1` option except `:name`, which is set to the using module. Defines:

| Function | Behaviour |
|---|---|
| `child_spec(overrides \\ [])` | `%{id: __MODULE__, start: {__MODULE__, :start_link, [overrides]}}` |
| `start_link(overrides \\ [])` | `RpcLoadBalancer.start_link/1` with the `use` options, `name: __MODULE__`, and `overrides` merged last |
| `get_members()` | `RpcLoadBalancer.get_members(__MODULE__)` |
| `select_node(opts \\ [])` | `RpcLoadBalancer.select_node(__MODULE__, opts)` |
| `call(node, module, fun, args, opts \\ [])` | `RpcLoadBalancer.call/5` with `load_balancer: __MODULE__` |
| `cast(node, module, fun, args, opts \\ [])` | `RpcLoadBalancer.cast/5` with `load_balancer: __MODULE__` |
| `call_on_random_node(filter, module, fun, args, opts \\ [])` | `RpcLoadBalancer.call_on_random_node/5` with `load_balancer: __MODULE__` |
| `cast_on_random_node(filter, module, fun, args, opts \\ [])` | `RpcLoadBalancer.cast_on_random_node/5` with `load_balancer: __MODULE__` |

### Functions

#### `start_link(opts)`

Starts a Supervisor for a single balancer instance. Its children are the selection algorithm's `child_specs/2` (if any) followed by the `RpcLoadBalancer.LoadBalancer` GenServer, under `:one_for_all`. Returns once the balancer has joined its `:pg` group.

**Options:**
- `:name` (required) — registered name for the balancer; also used as the `:pg` group name
- `:selection_algorithm` — module implementing `SelectionAlgorithm` (default: `SelectionAlgorithm.Random`)
- `:algorithm_opts` — keyword list forwarded to the algorithm's `init/2` and `child_specs/2` callbacks (default: `[]`)
- `:node_match_list` — controls whether **this** node joins the `:pg` group (default: `:all`)
  - `:all` — every node joins
  - `[String.t() | Regex.t()]` — joins only if `RpcLoadBalancer.NodeFilter.matches?/2` is true for at least one entry
- `:drain_timeout` — max milliseconds to wait for in-flight calls during shutdown (default: `15_000`; `:infinity` allowed)

**Returns:** `Supervisor.on_start()`

The GenServer is registered as `:"#{name}_server"`; the supervisor as `name`.

#### `get_members(load_balancer_name)`

Returns the deduplicated list of nodes with a live member process in the balancer's `:pg` group.

**Returns:**
- `{:ok, [node()]}` when members exist
- `{:error, %ErrorMessage{code: :service_unavailable}}` when the group is empty

#### `select_node(load_balancer_name, opts \\ [])`

Selects a node from the balancer's registered members using the configured algorithm. Does not make an RPC. Emits `[:rpc_load_balancer, :node_selected]`.

**Options:** all forwarded verbatim to the algorithm's `choose_from_nodes/3` (e.g. `key: "user:123"` for `HashRing`)

**Returns:**
- `{:ok, node()}` on success
- `{:error, %ErrorMessage{code: :service_unavailable}}` when no nodes are registered

For connection-tracking algorithms the caller must call `SelectionAlgorithm.release_node/3` after the work completes — see [Connection Tracking](../how-to/connection-tracking.md).

#### `call(node, module, fun, args, opts \\ [])`

Synchronous RPC. Wrapped in the `[:rpc_load_balancer, :rpc]` telemetry span.

- **Without `:load_balancer`** — `:erpc.call/5` to `node`.
- **With `:load_balancer`** — `node` is ignored. If `call_directly?` (option or config) is true, or the algorithm's `local?/0` is true, runs `apply(module, fun, args)` locally. Otherwise selects a member, tracks the call for draining, runs `:erpc.call/5`, then calls the algorithm's `release_node/2`. If no member is registered, retries per the retry options before failing.

**Options:**
- `:timeout` — call timeout in milliseconds (default: `10_000`)
- `:load_balancer` — name of a running load balancer to route through
- `:key` — forwarded to the selection algorithm (used by `HashRing`)
- `:call_directly?` — execute locally via `apply/3` (default: `RpcLoadBalancer.Config.call_directly?/0`)
- `:retry?`, `:retry_count`, `:retry_sleep` — no-route retry, see `RpcLoadBalancer.Retry` below

**Returns:**
- `{:ok, result}` on success
- `{:error, %ErrorMessage{code: :request_timeout}}` on `:erpc` timeout
- `{:error, %ErrorMessage{code: :service_unavailable}}` on `:noconnection`, other `:erpc` failures, or no members after retries
- `{:error, %ErrorMessage{code: :bad_request}}` on `:erpc` `:badarg`

#### `cast(node, module, fun, args, opts \\ [])`

Asynchronous fire-and-forget RPC. Same routing rules as `call/5`, using `:erpc.cast/4` remotely and `spawn/3` locally.

**Options:** `:load_balancer`, `:key`, `:call_directly?`, `:retry?`, `:retry_count`, `:retry_sleep`

**Returns:**
- `:ok` when dispatched
- `{:error, %ErrorMessage{}}` on failure to dispatch or no members after retries

#### `call_on_random_node(node_filter, module, fun, args, opts \\ [])`

Picks a random node from `Node.list/0` whose name matches `node_filter` (via `RpcLoadBalancer.NodeFilter.matches?/2` — substring or regex, honouring `excluded_node_patterns`), then runs `call/5` on it. If the current node matches the filter or `:call_directly?` is true, executes locally via `apply/3`.

Retries when no node matches, per the retry options.

**Options:**
- `:timeout` — call timeout in milliseconds
- `:load_balancer` — enrols the call in that balancer's connection draining (no effect on selection). Requires a balancer instance with that name to be running on the calling node
- `:call_directly?` — execute locally (default: from config)
- `:retry?`, `:retry_count`, `:retry_sleep` — see `RpcLoadBalancer.Retry`

**Returns:**
- `{:ok, result}` on success
- `{:error, %ErrorMessage{code: :service_unavailable, message: "no nodes in cluster found with that filter"}}` when nothing matches after retries
- any `call/5` error from the selected node

#### `cast_on_random_node(node_filter, module, fun, args, opts \\ [])`

Same as `call_on_random_node/5` but uses `cast/5` (or `spawn/3` locally).

**Returns:** `:ok` or `{:error, %ErrorMessage{}}`

---

## RpcLoadBalancer.Config

Reads application config with defaults. Override in `config/*.exs`:

```elixir
config :rpc_load_balancer,
  call_directly?: false,
  retry?: true,
  retry_count: 5,
  excluded_node_patterns: []
```

| Function | Key | Type | Default | Description |
|---|---|---|---|---|
| `call_directly?/0` | `:call_directly?` | `boolean()` | `false` | Execute load-balanced and random-node calls locally via `apply/3` / `spawn/3` |
| `retry?/0` | `:retry?` | `boolean()` | `true` | Enable no-route retry |
| `retry_count/0` | `:retry_count` | `non_neg_integer()` | `5` | Retries after the first attempt |
| `excluded_node_patterns/0` | `:excluded_node_patterns` | `[String.t()]` | `[]` | Node-name substrings excluded from filters that don't contain them (see `NodeFilter`) |

---

## RpcLoadBalancer.Retry

#### `with_retry(opts \\ [], fun)`

Calls `fun` until it returns something other than `:retry`, sleeping `:retry_sleep` between attempts. Returns the first non-`:retry` result, or `:error` once retries are exhausted.

**Options:**
- `:retry?` — enable retrying (default: `RpcLoadBalancer.Config.retry?/0`)
- `:retry_count` — retries after the first attempt; `non_neg_integer()` or `:infinity` (default: `RpcLoadBalancer.Config.retry_count/0`)
- `:retry_sleep` — milliseconds between attempts (default: `5_000`)

Used by `call/5`/`cast/5` for empty `:pg` groups and by the random-node helpers for empty filter results. Never retries a dispatched RPC.

---

## RpcLoadBalancer.NodeFilter

#### `matches?(node_name, filter, excluded_patterns \\ Config.excluded_node_patterns())`

Returns `true` when `to_string(node_name) =~ filter` **and** no excluded pattern is present in the node's short name (before `@`) but absent from the filter. `filter` may be a string (substring match) or a `Regex`; regex filters are checked for excluded patterns via `Regex.source/1`.

Used for `:node_match_list` membership and the `node_filter` argument of the random-node helpers.

---

## RpcLoadBalancer.Metrics

#### `metrics()`

Returns `[Telemetry.Metrics.t()]` ready for any reporter:

| Series | Type | Event | Tags |
|---|---|---|---|
| `rpc_load_balancer.rpc.request.start.count` | counter | `[:rpc_load_balancer, :rpc, :start]` | `node module function type load_balancer` |
| `rpc_load_balancer.rpc.request.stop.count` | counter | `[:rpc_load_balancer, :rpc, :stop]` | `+ status` |
| `rpc_load_balancer.rpc.duration.milliseconds` | distribution | `[:rpc_load_balancer, :rpc, :stop]` | `+ status`; buckets `0.1 … 60_000` ms |
| `rpc_load_balancer.node.selected.count` | counter | `[:rpc_load_balancer, :node_selected]` | `algorithm load_balancer node` |
| `rpc_load_balancer.node.selected.empty.count` | counter | `[:rpc_load_balancer, :node_selected, :empty]` | `algorithm load_balancer` |
| `rpc_load_balancer.node.pool_size` | distribution | `[:rpc_load_balancer, :node_selected]` (`members_count`) | `algorithm load_balancer` |

Full event/metadata reference: [Telemetry and Metrics](../how-to/telemetry-and-metrics.md).

---

## RpcLoadBalancer.LoadBalancer

GenServer started by `RpcLoadBalancer.start_link/1`. On `init/1` it seeds the drainer and counter index registries, records the algorithm in `AlgorithmCache`, runs the algorithm's `init/2`, joins the `:pg` group if `node_match_list` matches, and subscribes to `:pg` membership changes (`:pg.monitor/2`, OTP 25.1+). Join/leave notifications are forwarded to the algorithm's `on_node_change/2`. On `terminate/2` it leaves the group and blocks in `Drainer.drain/2` for up to `:drain_timeout`.

You don't call this module directly.

---

## RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

Behaviour plus dispatch layer. The dispatch functions (`init/3`, `choose_from_nodes/4`, `choose_nodes/5`, `on_node_change/3`, `release_node/3`, `local?/1`, `child_specs/3`, `caches/1`) take the algorithm module first, check `function_exported?/3` for optional callbacks, and supply defaults.

### Callbacks

#### Required

```elixir
@callback choose_from_nodes(load_balancer_name(), [node()], opts :: keyword()) :: node()
```

Pick one node from the member list. Called concurrently from every calling process. Options come from `select_node/2` (all of them) or `call/5`/`cast/5` (`:key`, `:call_directly?`, `:load_balancer` only).

#### Optional

```elixir
@callback init(load_balancer_name(), opts :: keyword()) :: :ok
```
Once at balancer startup, before joining `:pg`. Receives `algorithm_opts`.

```elixir
@callback choose_nodes(load_balancer_name(), [node()], pos_integer(), opts :: keyword()) :: [node()]
```
Pick `count` distinct nodes (replicas). Default: `Enum.shuffle/1 |> Enum.take(count)`.

```elixir
@callback on_node_change(load_balancer_name(), {:joined | :left, [node()]}) :: :ok
```
`:pg` membership changed. Default: no-op.

```elixir
@callback release_node(load_balancer_name(), node()) :: :ok
```
A load-balanced `call/5`/`cast/5` finished on `node`. Default: no-op.

```elixir
@callback local?() :: boolean()
```
`true` → skip selection and `:erpc`; run `apply/3` / `spawn/3` locally. Default: `false`.

```elixir
@callback child_specs(load_balancer_name(), opts :: keyword()) :: [Supervisor.child_spec()]
```
Children started under the balancer supervisor **before** the `LoadBalancer` GenServer. Default: `[]`.

```elixir
@callback caches() :: [module()]
```
`elixir_cache` modules the algorithm needs. The application supervisor starts them at boot for the **built-in** algorithms only. Default: `[]`.

### Dispatch helpers you may call

- `get_algorithm(name)` — `{:ok, module | nil}`; the algorithm recorded for a running balancer
- `choose_from_nodes(algorithm, name, nodes, opts \\ [])` — runs the callback and emits `[:rpc_load_balancer, :node_selected]` (or `[..., :empty]` for `[]`, then lets the algorithm raise)
- `choose_nodes(algorithm, name, nodes, count, opts \\ [])`
- `release_node(algorithm, name, node)`

---

## Built-in Algorithms

All live under `RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.*`. Costs from `bench/README.md` (8 nodes, single process, M1 Max).

### Random (default)

`Enum.random/1`. Stateless. ~0.11 μs.

Implements: `choose_from_nodes/3`

### RoundRobin

Cycles through the member list with a shared atomic counter (`CounterCache` slot 1). Auto-resets above 10,000,000. ~0.77 μs, constant.

Implements: `init/2`, `choose_from_nodes/3`

### WeightedRoundRobin

Round robin over an expanded list with each node repeated `weight` times. Weights stored in `:persistent_term` at `init/2`; the expanded list is cached in `WeightedRoundRobinCache` (ETS) and rebuilt after membership changes. Missing nodes default to weight 1. ~0.88 μs, constant.

**Algorithm options:** `weights: %{node() => pos_integer()}` (default `%{}`)

Implements: `init/2`, `choose_from_nodes/3`, `on_node_change/2`, `caches/0`

### LeastConnections

Per-node `:counters` in `CounterCache`. Single-pass scan for the lowest count, increment on select, decrement on `release_node/2`, reset on leave. ~1.18 μs, linear in members.

Implements: `init/2`, `choose_from_nodes/3`, `on_node_change/2`, `release_node/2`

### PowerOfTwo

Two random members, pick the one with fewer connections. Same counters as `LeastConnections`. ~1.32 μs, two reads regardless of size.

Implements: `init/2`, `choose_from_nodes/3`, `on_node_change/2`, `release_node/2`

### HashRing

Consistent hashing via [`libring`](https://hex.pm/packages/libring) (`:erlang.phash2/2` over a 2^32 range, `weight` virtual nodes per member). Routes by the `:key` option; falls back to random without one. `choose_nodes/4` returns N distinct nodes for a key. Weight in `:persistent_term`; the built ring cached in `HashRingCache` (ETS), invalidated on membership change and rebuilt lazily. ~2.02 μs, near-constant.

**Algorithm options:** `weight: pos_integer()` (default `128`)

Implements: `init/2`, `choose_from_nodes/3`, `choose_nodes/4`, `on_node_change/2`, `caches/0`

### LeastCpu

Routes to the member with the lowest cached CPU, picking randomly among nodes within `cpu_threshold` of the minimum. A per-balancer `LeastCpu.Poller` GenServer samples local CPU (`:cpu_sup.util/0`) and fetches remote members' readings via `:erpc.multicall/5` every `poll_interval`, writing to the node-keyed `NodeCpuCache`. Missing/stale entries read as 50%. ~12 μs, linear.

**Algorithm options:**
- `:poll_interval` (default `5_000`)
- `:poll_startup_jitter` (default `60_000`)
- `:cpu_cache_ttl` (default `10_000`)
- `:cpu_threshold` (default `5.0`)
- `:cpu_sampler` (default `&:cpu_sup.util/0`)

Telemetry: `[:rpc_load_balancer, :least_cpu, :poll, :start | :stop | :exception | :remote_error]`.

Implements: `init/2`, `choose_from_nodes/3`, `child_specs/2`, `caches/0`

### CallDirect

`local?/0` returns `true`, so load-balanced calls run `apply/3` and casts `spawn/3` on the local node. Nothing is selected, no `:pg` lookup. ~0.04 μs. For tests and single-node deployments.

Implements: `local?/0`, `choose_from_nodes/3` (returns `node()`; unused on the RPC path)

---

## RpcLoadBalancer.LoadBalancer.Drainer

Tracks in-flight load-balanced calls per balancer with an atomic counter (`DrainerCache`) so shutdown can wait for them.

- `register(load_balancer_name)` — returns the counter index for a balancer (allocating on first use)
- `track_call(index)` / `release_call(index)` — increment / decrement
- `in_flight_count(index)` — current count
- `drain(index, timeout \\ 15_000)` — poll every 50 ms until the count reaches 0; `:ok` or `{:error, :timeout}`

`call/5`, `cast/5`, and the random-node helpers (when given `:load_balancer`) wrap the RPC in `track_call`/`release_call` (in an `after` block). `LoadBalancer.terminate/2` calls `drain/2` after leaving `:pg`.

---

## Internal Modules

Not part of the public API; documented for contributors.

| Module | Backing | Purpose |
|---|---|---|
| RpcLoadBalancer.Application (`lib/rpc_load_balancer/application.ex`, `@moduledoc false`) | — | Starts the `:pg` scope and one `Cache` supervisor holding the core caches plus every built-in algorithm's `caches/0` |
| `RpcLoadBalancer.LoadBalancer.Pg` | `:pg` scope `:rpc_load_balancer` | Group name, `remote_members/1`, and `multicall/5` fan-out to remote members |
| `RpcLoadBalancer.LoadBalancer.AlgorithmCache` | `Cache.PersistentTerm` | `load_balancer_name → algorithm module` |
| `RpcLoadBalancer.LoadBalancer.IndexRegistry` | `Cache.PersistentTerm` + `:atomics` | Allocates stable integer indices for `CounterCache` / `DrainerCache` keys; raises an explanatory error if a balancer was never started on the node |
| `RpcLoadBalancer.LoadBalancer.CounterCache` | `Cache.Counter` (`:counters`, 1024 slots) | Round-robin slot counters and per-node connection counts; `get_node_count/2` reads `:counters` directly |
| `RpcLoadBalancer.LoadBalancer.DrainerCache` | `Cache.Counter` (256 slots) | In-flight call counts per balancer |
| `RpcLoadBalancer.LoadBalancer.HashRingCache` | `Cache.ETS` (raw `lookup/1` + `insert_raw/1`) | Built `libring` ring per balancer |
| `RpcLoadBalancer.LoadBalancer.WeightedRoundRobinCache` | `Cache.ETS` (raw) | `{member_list, expanded_list}` per balancer |
| `RpcLoadBalancer.LoadBalancer.NodeCpuCache` | `Cache.PersistentTerm` | `%{cpu: float, fetched_at: monotonic_ms}` per **node** (shared by all balancers) |
| `RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller` | GenServer | Periodic local sample + remote multicall for `LeastCpu` |
