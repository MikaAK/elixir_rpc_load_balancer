---
name: rpc_load_balancer--elixir--rpc-calls-load-balancer
description: Use when making cross-node RPC calls in Elixir with rpc_load_balancer — RpcLoadBalancer.call/cast, `use RpcLoadBalancer` modules, selection algorithms (Random, RoundRobin, WeightedRoundRobin, LeastConnections, PowerOfTwo, HashRing, LeastCpu, CallDirect), node filtering, retry, telemetry, or testing code that routes through a load balancer. Skip for single-node code that never crosses a node boundary.
---

# rpc_load_balancer — cross-node RPC with a `:pg` load balancer

Wraps `:erpc` with `{:ok, _} | {:error, %ErrorMessage{}}` and picks target nodes from `:pg` process groups (dead nodes vanish instantly — no `Node.list/0` heartbeat lag).

## Define a balancer (preferred)

```elixir
defmodule MyApp.LoadBalancer do
  @algorithm if Mix.env() === :test,
               do: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirect,
               else: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin

  use RpcLoadBalancer,
    selection_algorithm: @algorithm,
    node_match_list: ["worker"]          # only nodes whose name contains "worker" register as targets
end

# application.ex — LAST child so it deregisters + drains before Repo/Endpoint stop
children = [MyApp.Repo, MyAppWeb.Endpoint, MyApp.LoadBalancer]
```

Generated: `call/5`, `cast/5`, `select_node/1`, `get_members/0`, `call_on_random_node/5`, `cast_on_random_node/5`, `child_spec/1`, `start_link/1`. Balancer name == module name.

Ad-hoc form: `{RpcLoadBalancer, name: :my_lb, selection_algorithm: ...}` and pass `load_balancer: :my_lb` on each call.

## Call

```elixir
{:ok, result} = MyApp.LoadBalancer.call(node(), Mod, :fun, [arg], timeout: :timer.seconds(5))
:ok          = MyApp.LoadBalancer.cast(node(), Mod, :fun, [arg])

# HashRing: same key -> same node
{:ok, result} = MyApp.LoadBalancer.call(node(), Mod, :fun, [arg], key: user_id)

# direct, no balancer
{:ok, result} = RpcLoadBalancer.call(:"worker@host", Mod, :fun, [arg])

# any node whose name matches (Node.list/0 substring/regex), no balancer needed
{:ok, result} = RpcLoadBalancer.call_on_random_node("worker", Mod, :fun, [arg])
```

The `node` arg is ignored when routing through a balancer — pass `node()`.

Errors: `:request_timeout` (erpc timeout), `:service_unavailable` (noconnection / no members after retries), `:bad_request` (badarg).

## Pick an algorithm

| Need | Algorithm | Notes |
|---|---|---|
| default, cheapest | `Random` | |
| fair rotation | `RoundRobin` | atomic counter |
| capacity-weighted | `WeightedRoundRobin` | `algorithm_opts: [weights: %{:"n@h" => 3}]`, default 1 |
| fewest in-flight | `LeastConnections` (small pools) / `PowerOfTwo` (>8 nodes) | released automatically after `call/5`; manual `SelectionAlgorithm.release_node/3` if you used `select_node` |
| sticky by key | `HashRing` | pass `key:`; `algorithm_opts: [weight: 128]` vnodes |
| route around hot CPUs | `LeastCpu` | needs `:os_mon`; `algorithm_opts: [poll_interval:, cpu_cache_ttl:, cpu_threshold:, poll_startup_jitter:, cpu_sampler:]` |
| tests / single node | `CallDirect` | `apply/3` locally, no `:erpc`, no selection |

Custom: `@behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm`, required `choose_from_nodes/3`; optional `init/2`, `choose_nodes/4`, `on_node_change/2`, `release_node/2`, `local?/0`, `child_specs/2`, `caches/0`. `call/5` only forwards `:key` to the algorithm; `select_node/2` forwards everything.

## Retry / no-route

Empty pool (boot, rolling restart) → back off and retry, **never** retries a dispatched RPC.

```elixir
config :rpc_load_balancer, retry?: true, retry_count: 5      # + retry_sleep 5_000 ms default
MyApp.LoadBalancer.call(node(), Mod, :fun, [], retry?: false)                    # fail fast
MyApp.LoadBalancer.call(node(), Mod, :fun, [], retry_count: :infinity, retry_sleep: 250)
```

## Node filtering

- `node_match_list: ["worker", ~r/^ingest/]` — substring/regex; only decides whether *this* node registers as a target. Non-matching nodes can still call.
- `config :rpc_load_balancer, excluded_node_patterns: ["_qa"]` — `worker_qa@h` is dropped from filter `"worker"` but reachable via `"worker_qa"`. Applies to `node_match_list` and `call_on_random_node` filters.

## Testing

- Use `CallDirect` per balancer (compile-time attribute above) **or** `config :rpc_load_balancer, call_directly?: true` in `config/test.exs` (global, all balancers).
- `start_supervised!(MyApp.LoadBalancer)` / `start_supervised!({RpcLoadBalancer, name: :"lb_#{System.unique_integer([:positive])}", selection_algorithm: CallDirect})` — ready when it returns, no sleeps.
- Never `Application.put_env` in tests; use per-call `call_directly?: true` / `retry?: false` or `algorithm_opts` (`cpu_sampler: fn -> 10.0 end, poll_startup_jitter: 0`).

## Telemetry

- `[:rpc_load_balancer, :rpc, :start | :stop | :exception]` span on every call/cast — meta `type node module function load_balancer`, `status` on stop.
- `[:rpc_load_balancer, :node_selected]` per selection — meta `algorithm load_balancer node`, measure `members_count`.
- `RpcLoadBalancer.Metrics.metrics()` → drop into `PrometheusTelemetry` / `TelemetryMetricsPrometheus`.

## Gotchas

- Balancer last in the supervision tree (drains up to `drain_timeout: 15_000` after leaving `:pg`).
- `call_on_random_node(..., load_balancer: X)` only adds drain tracking; raises a descriptive `IndexRegistry` error if no balancer `X` runs on the calling node.
- Weights / hash-ring weight / LeastCpu opts are read once at start (`:persistent_term`) — restart the balancer to change them.
- Custom algorithms' `caches/0` are **not** auto-started; start your cache in your own tree or via `child_specs/2`.
- Hex docs: https://hexdocs.pm/rpc_load_balancer — how-tos for every algorithm, retry, telemetry, testing.
