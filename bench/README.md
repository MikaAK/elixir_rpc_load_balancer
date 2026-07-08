# Benchmarks

Benchee scripts that measure the cost of `choose_from_nodes/3` for every
selection algorithm in isolation — no `:pg` lookups, no network. The
synthetic node pool lets us scale cluster size up to 32 nodes while
keeping every other variable constant.

## Running

```sh
mix deps.get
MIX_ENV=dev mix run bench/select_node_bench.exs   # node-count sweep
MIX_ENV=dev mix run bench/contention_bench.exs    # parallel: 32
```

## What gets measured

| Script | Purpose |
|---|---|
| `select_node_bench.exs` | Pure single-process `choose_from_nodes/3` cost across 2 / 8 / 32 nodes. Captures wall time, allocations, reductions. |
| `contention_bench.exs` | Same call run with `parallel: 32` (3.2× oversubscribed on a 10-core M1) to surface lock-table / telemetry-handler contention. |

`bench/support.exs` boots the application, starts one load balancer per
algorithm, and pre-warms `CounterCache` and `NodeCpuCache` so we measure
steady-state behavior, not first-touch lazy-initialization. The
`LeastCpu` poller is configured with a 10-minute jitter and a fixed CPU
sampler so it never fires during the benchmark.

## Storage strategy

Selection-algorithm state has very different write frequency:

| State | Write frequency | Storage |
|---|---|---|
| Algorithm config (`weights`, `hash_ring_weight`, `cpu_opts`) | Once at `init/2`, never again | `:persistent_term` (per-algorithm namespace) |
| Hash ring | Every `on_node_change` | `Cache.ETS` via raw `lookup/1` + `insert_raw/1` |
| WRR expanded list | Every `on_node_change` | `Cache.ETS` via raw `lookup/1` + `insert_raw/1` |
| Connection counters | Per call | `:counters` (lock-free) |

`:persistent_term.put/2` triggers a global GC sweep, so it must only
be used for state that really is write-once. In a 1000-node cluster
with even 1–2 nodes flapping at any moment, putting the hash ring in
PT would mean continuous global GC. ETS writes are local, lock-free
under `write_concurrency: true`, and trigger no GC.

## Results — Apple M1 Max, Elixir 1.19.5 / OTP 28.3.3

### `select_node` — single process, 8 nodes

| Algorithm | ips | avg | median | p99 | memory |
|---|---:|---:|---:|---:|---:|
| `CallDirect` | 23.20 M | 0.04 μs | 0.04 μs | 0.08 μs | 0 KB |
| `Random` | 8.70 M | 0.11 μs | 0.08 μs | 0.17 μs | 0.34 KB |
| `RoundRobin` | 1.29 M | 0.77 μs | 0.71 μs | 0.96 μs | 1.05 KB |
| `WeightedRoundRobin` | 1.14 M | 0.88 μs | 0.79 μs | 1.04 μs | 1.18 KB |
| `LeastConnections` | 0.84 M | 1.18 μs | 1.13 μs | 1.38 μs | 1.84 KB |
| `PowerOfTwo` | 0.76 M | 1.32 μs | 1.25 μs | 1.88 μs | 1.70 KB |
| `HashRing` | 0.49 M | 2.02 μs | 1.75 μs | 5.38 μs | 0.27 KB |
| `LeastCpu` | 83 K | 12.04 μs | 9.71 μs | 66.92 μs | 7.36 KB |

### Scaling with cluster size (avg µs)

| Algorithm | 2 nodes | 8 nodes | 32 nodes | Notes |
|---|---:|---:|---:|---|
| `CallDirect` | 0.04 | 0.04 | 0.04 | constant — never touches the node list |
| `Random` | 0.12 | 0.11 | 0.13 | constant — `Enum.random/1` |
| `RoundRobin` | 0.79 | 0.77 | 0.82 | constant — atomic counter + `Enum.at/2` |
| `WeightedRoundRobin` | 0.87 | 0.88 | 1.02 | constant — cached expanded list |
| `HashRing` | 1.94 | 2.02 | 2.32 | near-constant — one ETS lookup + libring |
| `LeastConnections` | 0.61 | 1.18 | 3.34 | linear — one `:counters.get/2` per node |
| `PowerOfTwo` | 0.86 | 1.32 | 1.97 | sub-linear — 2 `:counters.get/2` |
| `LeastCpu` | 3.57 | 12.04 | 47.57 | linear — adapter read + decode per node |

### Parallel contention — 32 schedulers (3.2× oversubscribed), 8 nodes

| Algorithm | single avg | parallel avg | slowdown | p99 |
|---|---:|---:|---:|---:|
| `CallDirect` | 0.04 μs | 0.08 μs | 1.8× | 0.48 μs |
| `Random` | 0.11 μs | 0.43 μs | 3.7× | 4.78 μs |
| `RoundRobin` | 0.77 μs | 5.73 μs | 7.4× | 112.46 μs |
| `WeightedRoundRobin` | 0.88 μs | 5.95 μs | 6.8× | 117.58 μs |
| `LeastConnections` | 1.18 μs | 7.03 μs | 6.0× | 102.38 μs |
| `PowerOfTwo` | 1.32 μs | 7.52 μs | 5.7× | 103.38 μs |
| `HashRing` | 2.02 μs | 40.99 μs | 20.3× | 651.21 μs |
| `LeastCpu` | 12.04 μs | 56.76 μs | 4.7× | 656.66 μs |

## Improvements vs. the original implementation

| Algorithm | Before (8 nodes, single) | After | Speedup | Parallel-32 before | After | Speedup |
|---|---:|---:|---:|---:|---:|---:|
| `HashRing` | 28.73 μs | 2.02 μs | **14.2×** | 601.64 μs | 40.99 μs | **14.7×** |
| `LeastConnections` | 5.87 μs | 1.18 μs | **5.0×** | 37.23 μs | 7.03 μs | **5.3×** |
| `WeightedRoundRobin` | 2.78 μs | 0.88 μs | **3.2×** | 13.90 μs | 5.95 μs | **2.3×** |
| `LeastCpu` | 17.40 μs | 12.04 μs | 1.4× | 76.69 μs | 56.76 μs | 1.4× |
| `LeastConnections` (32 nodes) | 21.49 μs | 3.34 μs | **6.4×** | — | — | — |

## What was wrong, and what changed

1. **`Cache.get/1` wraps every read in `:telemetry.span/3`.** The
   span builds a metadata map, captures monotonic timestamps, runs
   inside a try/rescue, and dispatches `[..., :start]` and
   `[..., :stop]` events synchronously to every attached handler.
   Even with no handlers attached, that's ~1–2 μs of pure
   bookkeeping per cache read; under `parallel: 32` the same
   handler-table ETS gets hammered by every scheduler. Fix: caches
   that get hit on the hot path now expose accessors that go
   straight to the adapter (or to `:counters` / `:ets`), skipping
   the wrapper. `Cache.get/1` and its telemetry span are still
   available for cold paths.

2. **`HashRing` lived in a `Cache.ETS` table read via `Cache.get/1`.**
   ETS reads with `read_concurrency: true` are fine, but the
   wrapper paid telemetry cost per read AND `Cache.TermEncoder`
   round-tripped the multi-KB ring through `:erlang.term_to_binary/1`
   on every put. Fix: `HashRingCache` still uses `Cache.ETS`, but
   reads use the macro-injected `lookup/1` (a direct `:ets.lookup/2`)
   and writes use `insert_raw/1`, both of which skip the wrapper
   AND the encoder. The ring is stored as a raw term.

3. **`LeastConnections` allocated 34 KB per call at 32 nodes.** The
   `Enum.map → Enum.min_by → elem(0)` chain rebuilt a fresh
   `[{node, count}, …]` list on every selection. Fix: rewrite as a
   single `Enum.reduce/3` carrying `{best_node, best_count}` —
   one tuple instead of N. Combined with the `:counters.get/2`
   fast path on `CounterCache`, this is also lock-free.

4. **`WeightedRoundRobin` rebuilt the expanded list every call.**
   `expand_node_list/2` ran `List.duplicate/2` per selection. Fix:
   cache the expanded list in `WeightedRoundRobinCache` (also
   `Cache.ETS` with `lookup/1` + `insert_raw/1`), keyed by the
   running node-list. Topology change invalidates; steady-state hot
   path is one ETS lookup + atomic counter + `Enum.at/2`.

5. **Algorithm config (`hash_ring_weight`, `weights`, `cpu_opts`)
   moved into per-algorithm `:persistent_term` namespaces.** These
   are written once at `init/2` and never again, which is exactly
   what `:persistent_term` is designed for. The old shared
   `LoadBalancerOptsCache` is gone.

`LeastCpu` keeps the largest per-call cost — its decode-per-node
path through `Cache.TermEncoder` is unchanged. A future pass could
move `NodeCpuCache` to ETS-backed storage with raw `lookup/1` (same
trick as `HashRingCache`) so the decode disappears.

## Caveats

- Single-host benchmark — does not capture `:pg` membership churn or
  `:erpc` round-trip cost.
- M1 Max is a fast machine; absolute numbers will differ on
  production hardware, but ratios should hold.
- `LeastCpu` results assume a warm `NodeCpuCache`. Cache misses fall
  back to a 50% default and would not change the per-call cost.
