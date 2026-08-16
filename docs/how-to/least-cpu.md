# How to Route by CPU Load with LeastCpu

The `LeastCpu` algorithm routes calls to whichever member node currently has the lowest CPU utilization. Use it when CPU pressure — not connection count — is the signal that predicts a slow response, e.g. compute-heavy report generation or mixed workloads where some nodes also run background jobs.

## Start a balancer with LeastCpu

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :cpu_balancer,
    selection_algorithm: SelectionAlgorithm.LeastCpu,
    algorithm_opts: [
      poll_interval: 5_000,
      cpu_cache_ttl: 10_000,
      cpu_threshold: 5.0
    ]
  )
```

`LeastCpu` samples CPU with `:cpu_sup.util/0` from `:os_mon`, which `rpc_load_balancer` already declares as an extra application. If you build releases with an explicit application list, make sure `:os_mon` is included.

## How it works

Selection never touches the network. A background `Poller` GenServer — started per balancer via the algorithm's `child_specs/2` — does the slow work:

1. Every `poll_interval` ms it samples the local CPU and writes it to `NodeCpuCache`
2. It then runs one `:erpc.multicall/5` against every **remote** member of the balancer, asking each for its cached local reading, and stores those too (2 s per-call timeout, so a poll cycle stays bounded regardless of cluster size)

`choose_from_nodes/3` reads each member's cached entry, finds the minimum, and picks **randomly among all nodes within `cpu_threshold` percentage points of that minimum**. The random band prevents a thundering herd onto a single "coldest" node between polls.

An entry that is missing, or older than `cpu_cache_ttl`, is treated as 50% — a neutral value that neither attracts nor repels traffic until the next poll refreshes it.

`NodeCpuCache` is keyed by node, not by balancer: every `LeastCpu` balancer in the VM shares and co-warms the same readings.

## Options

All options go in `algorithm_opts`:

| Option | Default | Description |
|---|---|---|
| `:poll_interval` | `5_000` | Milliseconds between poll cycles |
| `:poll_startup_jitter` | `60_000` | Max random delay before the **first** poll. Spreads out the initial multicall storm when a whole cluster boots at once. Set `0` to poll immediately (tests) |
| `:cpu_cache_ttl` | `10_000` | Max age in ms before a cached reading counts as missing (falls back to 50%) |
| `:cpu_threshold` | `5.0` | Width in percentage points of the "close enough to the minimum" band selection picks from randomly |
| `:cpu_sampler` | `&:cpu_sup.util/0` | Zero-arity function returning a numeric CPU percent. Swap it to plug in another metric source, or return a constant in tests |

Keep `cpu_cache_ttl` comfortably above `poll_interval` (2× is the default ratio) so a single slow or missed poll doesn't flip the whole pool to the neutral default.

## Cold start behaviour

Until the first poll completes, every node reads as 50%, so `LeastCpu` behaves like `Random`. With the default 60 s startup jitter that window can be up to a minute — set `poll_startup_jitter: 0` if you'd rather take the multicall burst up front and start steering immediately.

## Test setup

Pin the sampler and disable jitter so selection is deterministic and fast:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :cpu_test_lb,
    selection_algorithm: SelectionAlgorithm.LeastCpu,
    algorithm_opts: [
      poll_startup_jitter: 0,
      poll_interval: 100,
      cpu_sampler: fn -> 12.5 end
    ]
  )
```

If the sampler raises or returns a non-number, the poller logs a warning and stores 50%.

## Telemetry

The poller emits events under `[:rpc_load_balancer, :least_cpu, :poll]`:

| Event | Measurements | Metadata |
|---|---|---|
| `[..., :poll, :start]` / `[..., :poll, :stop]` / `[..., :poll, :exception]` | span (`:duration` on stop) | `%{load_balancer_name: name}` |
| `[..., :poll, :remote_error]` | `%{count: 1}` | `%{load_balancer_name: name, node: remote, kind: :exit \| :error}` |

`kind: :exit` covers connectivity failures (timeout, noconnection); `:error` covers remote raises and unexpected result shapes. These events are **not** included in `RpcLoadBalancer.Metrics.metrics/0` — attach a handler or define your own `Telemetry.Metrics` entries if you want them exported.

## Cost

`LeastCpu` is the most expensive built-in algorithm per selection (~12 μs at 8 nodes, linear in cluster size — one cache read plus decode per member). It is still far cheaper than the RPC it wraps, but if you are selecting millions of times per second on a large cluster prefer `PowerOfTwo` or `HashRing`. See `bench/README.md` for the full numbers.
