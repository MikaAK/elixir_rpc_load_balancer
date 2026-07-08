## 0.3.4

### Features
- Add `use RpcLoadBalancer` to define a named load balancer module exposing the full `RpcLoadBalancer` interface bound to a fixed configuration, with `child_spec/1`/`start_link/1` for direct supervision. (#8)
- Retry no-route conditions on the load-balancer-routed `call/5` and `cast/5` paths (the `load_balancer:` option), backing off per `:retry?`/`:retry_count`/`:retry_sleep` instead of failing immediately; non-selection errors pass through un-retried. (#8)
- Support `retry_count: :infinity` in `RpcLoadBalancer.Retry.with_retry/2` (previously raised `ArithmeticError`). (#8)
- Add configurable, filter-relative node exclusion via `config :rpc_load_balancer, excluded_node_patterns: [...]` (default `[]`). A node whose short name carries an excluded pattern is dropped from any filter that does not itself carry it, while a filter carrying the pattern still reaches it. All node matching routes through `RpcLoadBalancer.NodeFilter.matches?/2,3`. (#10)

### Fixes
- Raise a clear, actionable error from `IndexRegistry.get_or_register/2` when the cache's index counter was never initialized, naming the missing cache/node instead of an opaque `:persistent_term` `ArgumentError`. (#9)
- Bypass telemetry on hot reads and use single-pass algorithm selection. (#2)

## 0.3.3

### Features
- Retry no-route conditions on the load-balancer-routed `RpcLoadBalancer.call/5` and `cast/5` paths (the `load_balancer:` option). When `select_node/2` finds no registered members (`:service_unavailable`), the call now backs off and retries per the `:retry?` / `:retry_count` / `:retry_sleep` options instead of failing immediately — matching the resilience the random-node path already had. Useful for cluster boot and rolling restarts where members register slightly after callers start routing. Non-selection errors (e.g. `:erpc` transport failures) pass through un-retried.
- Support `retry_count: :infinity` in `RpcLoadBalancer.Retry.with_retry/2`. Previously `:infinity` raised `ArithmeticError` (`:infinity - 1`); it now retries without decrementing until the function stops returning `:retry`.

>>>>>>> 91b9489 (feat(metrics): extend duration buckets to 30s + 60s (#6))
## 0.3.2

### Features
- Extend `RpcLoadBalancer.Metrics` duration histogram buckets to `30_000` and `60_000` ms. Previously the top bucket was `10_000` ms — calls exceeding 10s landed only in the `+Inf` bucket so `histogram_quantile/2` lost precision above 10s. Long-running RPCs (heavy reports, large data transfers, or any caller with a `:timeout` opt above the default 10s) now have meaningful p95/p99 measurements up to 60s.

## 0.3.1

### Features
- Emit `[:rpc_load_balancer, :node_selected]` telemetry after every successful pick by `SelectionAlgorithm.choose_from_nodes/4`. Measurements: `count: 1, members_count: pool_size`. Metadata: `:algorithm` (the algorithm module atom — e.g. `RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin`), `:load_balancer`, `:node`. Reveals selection skew, per-algorithm call mix, and cluster pool size over time.
- Emit `[:rpc_load_balancer, :node_selected, :empty]` when the algorithm is invoked with an empty member list. Telemetry fires first, then the algorithm raises whatever it would have raised (e.g. `Enum.EmptyError` from `Random`) — original contract preserved.
- Add `rpc_load_balancer.node.selected.count`, `rpc_load_balancer.node.selected.empty.count`, and `rpc_load_balancer.node.pool_size` to `RpcLoadBalancer.Metrics.metrics/0`.
- Widen the duration histogram buckets to cover sub-millisecond cluster RPC: `0.1, 0.5, 1, 2.5, 5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000` ms (was `1, 5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000` — local-cluster calls hit the floor at 1ms so quantiles capped at 5ms in dashboards).

## 0.3.0

### Features
- Wrap `RpcLoadBalancer.call/5` and `RpcLoadBalancer.cast/5` in `:telemetry.span/3` under the prefix `[:rpc_load_balancer, :rpc]`. Emits `:start`, `:stop` (with `:duration` measurement), and `:exception` events. Metadata: `:type` (`:call` or `:cast`), `:node`, `:module` (`inspect/1`'d), `:function`, `:load_balancer` (nullable), and on `:stop` a `:status` derived from the result tuple (`:ok`, `ErrorMessage.code`, or `:error`).
- Add `RpcLoadBalancer.Metrics` with `metrics/0` returning ready-to-register `Telemetry.Metrics` definitions for `rpc_load_balancer.rpc.request.start.count`, `rpc_load_balancer.rpc.request.stop.count`, and `rpc_load_balancer.rpc.duration.milliseconds`. Drop into any `PrometheusTelemetry` supervisor.
- Declare `:telemetry` and `:telemetry_metrics` as direct dependencies (previously transitive via `:elixir_cache`).

## 0.2.2

### Features
- Add `LeastCpu` selection algorithm that routes calls to the node with the lowest CPU utilization, sampled via `:cpu_sup` and cached in `:persistent_term`
- Add optional `child_specs/2` callback to the `SelectionAlgorithm` behaviour so algorithms can contribute their own supervised children

### Fixes
- Ensure the configured selection algorithm module is loaded before checking for `child_specs/2`, preventing startup races
- Use `Cache.PersistentTerm` for `NodeCpuCache` and fix the `:cpu_sup` apply call to stabilize CPU sampling

## 0.2.1

### Features
- Add `CallDirect` selection algorithm for local-node execution without `:erpc` overhead
- Add `Drainer` module for graceful connection draining with in-flight call tracking
- Add `IndexRegistry` for lock-free index allocation using `:atomics` and `:persistent_term`
- Add `Retry` module with configurable retry logic for RPC operations
- Add `Config` module for centralized application configuration defaults
- Add `ValueCache` backed by `Cache.PersistentTerm`
- Add `call_directly?` option to `call/5`, `cast/5`, `call_on_random_node/5`, and `cast_on_random_node/5`
- Add `select_node/2` to the public API

### Refactors
- Consolidate cache initialization into `RpcLoadBalancer` supervisor
- Extract retry logic from `LoadBalancer` into dedicated `Retry` module
- Simplify selection algorithms (`LeastConnections`, `PowerOfTwo`, `RoundRobin`, `WeightedRoundRobin`) by leveraging shared caches
- Promote `RpcLoadBalancer` to a `Supervisor` managing caches and the load balancer GenServer

### Docs
- Add `testing-with-call-direct` how-to guide
- Update architecture docs, reference docs, and getting started tutorial for new API

## 0.1.0
- Initial Release
