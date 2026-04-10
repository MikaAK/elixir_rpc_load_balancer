# Least CPU Selection Algorithm — Design Spec

## Overview

A new selection algorithm for `rpc_load_balancer` that routes RPC calls to the node with the lowest CPU utilization. Each node samples its own CPU metric and stores it locally. A background poller on each node fetches remote nodes' metrics via `:erpc` and caches them. Selection reads from cache, with inline refresh for stale entries.

## Architecture

### New Modules

| Module | Type | Purpose |
|--------|------|---------|
| `SelectionAlgorithm.LeastCpu` | Algorithm (behaviour impl) | Node selection based on CPU metrics |
| `SelectionAlgorithm.LeastCpu.Poller` | GenServer | Samples local CPU + fetches remote CPU on a timer |
| `LoadBalancer.NodeCpuCache` | Cache (ETS via `elixir_cache`) | Stores CPU metrics for all nodes (local and remote) |

### Behaviour Extension

`SelectionAlgorithm` gets a new optional callback:

```elixir
@callback child_specs(load_balancer_name(), opts :: keyword()) :: [Supervisor.child_spec()]
@optional_callbacks [child_specs: 2, ...]
```

A dispatch function `SelectionAlgorithm.child_specs/3` returns `[]` if the algorithm doesn't export it.

### Supervisor Changes

`RpcLoadBalancer.init/1` is modified to:

1. Start caches (existing + `NodeCpuCache`)
2. Start algorithm child specs (from `child_specs/2` if exported)
3. Start `LoadBalancer` GenServer

This ordering ensures the poller and cache are running before the GenServer calls `algorithm.init/2`.

## NodeCpuCache

Single ETS-backed cache holding CPU metrics for all nodes (local and remote).

- **Adapter**: ETS via `elixir_cache`
- **Key**: `{load_balancer_name, node}`
- **Value**: `%{cpu: float(), fetched_at: integer()}`

Both local and remote metrics live in the same cache. The remote `:erpc` call targets `NodeCpuCache.get({load_balancer_name, node()})` on the remote node, which works because every node's Poller writes the local CPU into this same cache.

## LeastCpu.Poller

A GenServer started as a child dependency of the `LeastCpu` algorithm.

### Responsibilities

On each timer tick:

1. Sample local CPU and write to `NodeCpuCache` with key `{lb_name, node()}`
2. Get current members via `:pg`
3. For each remote node, `:erpc.call` to `NodeCpuCache.get({lb_name, remote_node})` (2s timeout)
4. Write successful results to `NodeCpuCache` with key `{lb_name, remote_node}`
5. Failed fetches are left as-is (stale data persists until TTL check in selection)

### Metric Sources

Configurable via `algorithm_opts[:metric_source]`:

- `:scheduler_utilization` (default) — `:scheduler.utilization(1)`, averaged across all schedulers. No extra dependencies.
- `:cpu_sup` — `:cpu_sup.util/0`, returns system-wide CPU percentage. Requires the `os_mon` application.

## LeastCpu Algorithm

Implements `@behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm`.

### Callbacks

- **`child_specs/2`** — Returns child specs for `Poller`
- **`init/2`** — No-op (poller is already running)
- **`choose_from_nodes/3`**:
  1. Read CPU from `NodeCpuCache` for each node in `node_list`
  2. For entries missing or older than `cpu_cache_ttl`, do inline `:erpc.call` to the remote node's `NodeCpuCache` (2s timeout). On failure, assign `50.0` (midpoint default).
  3. Find the minimum CPU value
  4. Collect all nodes within `cpu_threshold` percentage points of the minimum
  5. `Enum.random/1` from that band
- **`on_node_change/2`** — On `:left`, remove departed nodes from `NodeCpuCache`
- **No `release_node/2`** — CPU is not transactional with selection

### Configuration

All options passed via `algorithm_opts`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:poll_interval` | `pos_integer()` | `5_000` | Background poll frequency in ms |
| `:cpu_cache_ttl` | `pos_integer()` | `10_000` | Max age (ms) before inline refresh is triggered |
| `:metric_source` | `:scheduler_utilization \| :cpu_sup` | `:scheduler_utilization` | CPU metric source |
| `:cpu_threshold` | `float()` | `5.0` | "Close enough" band width in percentage points |

### Selection Example

Given nodes with CPU values `%{a: 22.0, b: 25.0, c: 48.0}` and threshold `5.0`:

- Minimum is `22.0`, band is `22.0..27.0`
- Nodes `a` (22.0) and `b` (25.0) are in the band
- Random selection between `a` and `b`

## Unknown/Stale Node Handling

- Nodes with no cached CPU data or stale data that fails inline refresh: assigned `50.0` (midpoint)
- This treats unknown nodes neutrally — neither preferred nor penalized

## Usage Example

```elixir
RpcLoadBalancer.start_link(
  name: :my_lb,
  selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu,
  algorithm_opts: [
    poll_interval: 5_000,
    cpu_cache_ttl: 10_000,
    metric_source: :scheduler_utilization,
    cpu_threshold: 5.0
  ]
)
```
