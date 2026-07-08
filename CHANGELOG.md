## 0.4.2

### Features
- Add configurable, filter-relative node exclusion via `config :rpc_load_balancer, excluded_node_patterns: [...]` (default `[]`, no behavior change). A node whose short name carries an excluded pattern is dropped from any filter that does not itself carry that pattern, while a filter that carries the pattern still reaches it. All filter-based routing (`call_on_random_node/5`, `cast_on_random_node/5`), the current-node local-apply short-circuit, and named-load-balancer `node_match_list` membership now route through the shared `RpcLoadBalancer.NodeFilter.matches?/2,3` predicate. Use case: keep QA nodes named `<type>_qa@host` out of the prod `<type>` routing set and out of prod ownership elections, while a `<type>_qa` filter can still target them. Previously all matching used bare substring (`to_string(node) =~ filter`), so `<type>_qa@host` was indistinguishable from `<type>@host` for a `<type>` filter.

## 0.4.1

### Fixes
- Raise a clear, actionable error from `RpcLoadBalancer.LoadBalancer.IndexRegistry.get_or_register/2` when the cache's index counter was never initialized. Previously, routing a call through the drainer (the `load_balancer:` option on `call_on_random_node/5` or `cast_on_random_node/5`) on a node where no `RpcLoadBalancer` load-balancer instance is running raised an opaque `ArgumentError` from `:persistent_term.get/1` (`no persistent term stored with this key`), giving no hint about the cause. The error now names the missing cache and node and points to the two fixes: start an `{RpcLoadBalancer, name: ...}` child on the node, or drop the `:load_balancer` option.

## 0.4.0

### Features
- Add `use RpcLoadBalancer` to define a named load balancer module that exposes the full `RpcLoadBalancer` interface (`call/5`, `cast/5`, `call_on_random_node/5`, `cast_on_random_node/5`, `select_node/1`, `get_members/0`) bound to a fixed configuration, plus `child_spec/1` and `start_link/1` so it supervises directly (`children = [MyApp.LoadBalancer]`). Each generated function sets `:load_balancer` to the using module, so callers route by `key:` without repeating the LB name. Mirrors `RpcLoadBalancer`'s return shapes exactly. Modeled on `use Ecto.Repo`.
- Retry no-route conditions on the load-balancer-routed `RpcLoadBalancer.call/5` and `cast/5` paths (the `load_balancer:` option). When `select_node/2` finds no registered members (`:service_unavailable`), the call now backs off and retries per the `:retry?` / `:retry_count` / `:retry_sleep` options instead of failing immediately — matching the resilience the random-node path already had. Useful for cluster boot and rolling restarts where members register slightly after callers start routing. Non-selection errors (e.g. `:erpc` transport failures) pass through un-retried.
- Support `retry_count: :infinity` in `RpcLoadBalancer.Retry.with_retry/2`. Previously `:infinity` raised `ArithmeticError` (`:infinity - 1`); it now retries without decrementing until the function stops returning `:retry`.

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
