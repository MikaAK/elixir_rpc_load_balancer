# How to Collect Telemetry and Metrics

`rpc_load_balancer` instruments RPC calls and node selection with `:telemetry`, and ships `Telemetry.Metrics` definitions you can hand to any reporter (Prometheus, StatsD, LiveDashboard).

## Register the bundled metrics

`RpcLoadBalancer.Metrics.metrics/0` returns a list of `Telemetry.Metrics` structs. Add them to your reporter — with `PrometheusTelemetry`:

```elixir
# in your application.ex
children = [
  {PrometheusTelemetry,
   exporter: [enabled?: prod?()],
   metrics: [
     RpcLoadBalancer.Metrics.metrics(),
     PrometheusTelemetry.Metrics.VM.metrics()
   ]}
]
```

Or with `TelemetryMetricsPrometheus` / LiveDashboard:

```elixir
{TelemetryMetricsPrometheus, metrics: RpcLoadBalancer.Metrics.metrics()}
```

That exposes:

| Series | Type | Tags | Meaning |
|---|---|---|---|
| `rpc_load_balancer.rpc.request.start.count` | counter | `node module function type load_balancer` | RPCs started |
| `rpc_load_balancer.rpc.request.stop.count` | counter | `... + status` | RPCs completed |
| `rpc_load_balancer.rpc.duration.milliseconds` | distribution | `... + status` | RPC latency; buckets from 0.1 ms to 60 s |
| `rpc_load_balancer.node.selected.count` | counter | `algorithm load_balancer node` | Selections per target — reveals skew |
| `rpc_load_balancer.node.selected.empty.count` | counter | `algorithm load_balancer` | Selection attempted against an empty pool |
| `rpc_load_balancer.node.pool_size` | distribution | `algorithm load_balancer` | Member count observed at selection time |

`:module` is the `inspect/1`'d module name (a string), and `:load_balancer` is `nil` for direct (non-balanced) calls — both are bounded, so cardinality stays sane. `:node` is one label per cluster member.

## Raw events

If you want to attach your own handlers, these are the events.

### RPC span — `[:rpc_load_balancer, :rpc, ...]`

Every `RpcLoadBalancer.call/5` and `cast/5` (direct or load-balanced, including through `use RpcLoadBalancer` modules and the random-node helpers) is wrapped in a `:telemetry.span/3`:

| Event | Measurements | Notes |
|---|---|---|
| `[:rpc_load_balancer, :rpc, :start]` | `system_time` | |
| `[:rpc_load_balancer, :rpc, :stop]` | `duration` (native units) | adds `:status` to metadata |
| `[:rpc_load_balancer, :rpc, :exception]` | `duration` | remote `:erpc` failures come back as `{:error, ...}` and land in `:stop`; this fires when the wrapped work raises locally — e.g. `apply/3` under `CallDirect` / `call_directly?` |

Metadata on all three:

| Key | Value |
|---|---|
| `:type` | `:call` or `:cast` |
| `:node` | the node argument passed to `call/5`/`cast/5` — for load-balanced calls this is the *caller's* argument (usually `node()`), not the selected target. The random-node helpers call `call/5` internally with the node they picked, so there `:node` is the real target and `:load_balancer` is `nil` |
| `:module` | `inspect(module)` |
| `:function` | function name atom |
| `:load_balancer` | balancer name / module, or `nil` |
| `:status` (stop only) | `:ok`, the `ErrorMessage` code (`:request_timeout`, `:service_unavailable`, `:bad_request`), or `:error` |

For load-balanced calls the span covers the whole routed operation, including any no-route retry sleeps.

### Node selection — `[:rpc_load_balancer, :node_selected]`

Emitted after every successful `choose_from_nodes/3` (custom algorithms included):

- Measurements: `%{count: 1, members_count: pool_size}`
- Metadata: `%{algorithm: module, load_balancer: name, node: selected_node}`

`[:rpc_load_balancer, :node_selected, :empty]` fires when an algorithm is invoked with an empty member list (measurements `%{count: 1}`, metadata without `:node`). Through the public API this can't happen — `select_node/2` returns an error before selection — but the event exists so direct users of `SelectionAlgorithm.choose_from_nodes/4` still see the miss.

Selection events are **not** emitted when the balancer runs `CallDirect` or `call_directly?` is set — nothing is selected.

### LeastCpu poller — `[:rpc_load_balancer, :least_cpu, :poll, ...]`

`:start`/`:stop`/`:exception` span per poll cycle plus `:remote_error` per failed remote fetch. Not part of `Metrics.metrics/0`. See [Route by CPU Load with LeastCpu](least-cpu.md).

## Attach a handler directly

```elixir
:telemetry.attach(
  "log-slow-rpcs",
  [:rpc_load_balancer, :rpc, :stop],
  fn _event, %{duration: duration}, metadata, _config ->
    ms = System.convert_time_unit(duration, :native, :millisecond)

    if ms > 1_000 do
      Logger.warning("slow rpc #{metadata.module}.#{metadata.function} #{ms}ms status=#{metadata.status}")
    end
  end,
  nil
)
```

## What is deliberately not instrumented

The hot path inside selection algorithms reads caches through raw adapter calls (`:counters.get/2`, `:ets.lookup/2`, `:persistent_term.get/2`) rather than `elixir_cache`'s telemetry-wrapped `get/1`. You get one `node_selected` event per selection, not one per cache read — see `bench/README.md` for why.
