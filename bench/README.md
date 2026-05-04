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

## Results — Apple M1 Max, Elixir 1.19.5 / OTP 28.3.3

### `select_node` — single process, 8 nodes

| Algorithm | ips | avg | median | p99 | memory |
|---|---:|---:|---:|---:|---:|
| `CallDirect` | 23.77 M | 0.04 μs | 0.04 μs | 0.08 μs | 0 KB |
| `Random` | 9.07 M | 0.11 μs | 0.08 μs | 0.13 μs | 0.34 KB |
| `HashRing` | 4.01 M | 0.25 μs | 0.21 μs | 0.33 μs | 0.28 KB |
| `RoundRobin` | 1.26 M | 0.79 μs | 0.75 μs | 0.96 μs | 1.05 KB |
| `WeightedRoundRobin` | 1.21 M | 0.83 μs | 0.75 μs | 0.96 μs | 1.08 KB |
| `LeastConnections` | 0.81 M | 1.23 μs | 1.08 μs | 1.46 μs | 1.84 KB |
| `PowerOfTwo` | 0.77 M | 1.30 μs | 1.21 μs | 1.83 μs | 1.70 KB |
| `LeastCpu` | 74 K | 13.46 μs | 10.92 μs | 67.71 μs | 7.36 KB |

### Scaling with cluster size (avg µs)

| Algorithm | 2 nodes | 8 nodes | 32 nodes | Notes |
|---|---:|---:|---:|---|
| `CallDirect` | 0.04 | 0.04 | 0.04 | constant — never touches the node list |
| `Random` | 0.14 | 0.11 | 0.14 | constant — `Enum.random/1` on a list |
| `HashRing` | 0.22 | 0.25 | 0.22 | constant — `:persistent_term` ring lookup |
| `RoundRobin` | 0.82 | 0.79 | 0.84 | constant — atomic counter + `Enum.at/2` |
| `WeightedRoundRobin` | 0.83 | 0.83 | 0.90 | constant — cached expanded list |
| `LeastConnections` | 0.64 | 1.23 | 3.27 | linear (now in `:counters` reads) |
| `PowerOfTwo` | 0.82 | 1.30 | 1.94 | sub-linear — 2 `:counters` reads |
| `LeastCpu` | 5.0 | 13.46 | 51.06 | linear — `:persistent_term` read + decode per node |

### Parallel contention — 32 schedulers (3.2× oversubscribed), 8 nodes

| Algorithm | single avg | parallel avg | slowdown | p99 |
|---|---:|---:|---:|---:|
| `CallDirect` | 0.04 μs | 0.07 μs | 1.7× | 0.47 μs |
| `Random` | 0.11 μs | 0.40 μs | 3.6× | 4.42 μs |
| `HashRing` | 0.25 μs | 2.52 μs | 10.1× | 47.71 μs |
| `RoundRobin` | 0.79 μs | 5.67 μs | 7.2× | 109.04 μs |
| `WeightedRoundRobin` | 0.83 μs | 5.94 μs | 7.2× | 114.54 μs |
| `PowerOfTwo` | 1.30 μs | 7.35 μs | 5.7× | 98.79 μs |
| `LeastConnections` | 1.23 μs | 7.50 μs | 6.1× | 105.33 μs |
| `LeastCpu` | 13.46 μs | 67.43 μs | 5.0× | 752.07 μs |

## Improvements vs. the original implementation

| Algorithm | Before (8 nodes, single) | After | Speedup | Parallel-32 before | After | Speedup |
|---|---:|---:|---:|---:|---:|---:|
| `HashRing` | 28.73 μs | 0.25 μs | **115×** | 601.64 μs | 2.52 μs | **240×** |
| `LeastConnections` | 5.87 μs | 1.23 μs | **4.8×** | 37.23 μs | 7.50 μs | **5.0×** |
| `WeightedRoundRobin` | 2.78 μs | 0.83 μs | **3.4×** | 13.90 μs | 5.94 μs | **2.3×** |
| `LeastCpu` | 17.40 μs | 13.46 μs | 1.3× | 76.69 μs | 67.43 μs | 1.1× |
| `LeastConnections` (32 nodes) | 21.49 μs | 3.27 μs | **6.6×** | — | — | — |

## What was wrong, and what changed

1. **`Cache.get/1` wraps every read in `:telemetry.span/3`.** The
   span builds metadata maps, captures timestamps, and dispatches to
   every attached handler. For sub-microsecond operations this
   dominates the read cost; under parallel load the handler dispatch
   becomes a serialization point. Fix: every cache that's read on the
   hot path now exposes a `lookup_*` function that goes straight to the
   adapter, skipping the telemetry wrapper. Counters do
   `:counters.get/2`, persistent-term reads do
   `:persistent_term.get/2` + `Cache.TermEncoder.decode/1`.
2. **`HashRing` lived in a `Cache.ETS` table.** ETS reads with
   `read_concurrency: true` are fast, but the cached value still goes
   through the telemetry wrapper, and the ring itself is read-mostly
   (write only on topology change). Fix: store the ring directly in
   `:persistent_term` keyed by the load-balancer name. Reads are now
   a single zero-copy term lookup. Topology changes pay one global GC
   sweep — but topology changes are rare and selection runs millions
   of times per second.
3. **`LeastConnections` allocated 34 KB per call at 32 nodes.** The
   `Enum.map → Enum.min_by → elem(0)` chain rebuilt a fresh
   `[{node, count}, …]` list on every selection. Fix: rewrite as a
   single `Enum.reduce/3` that carries `{best_node, best_count}` —
   one tuple instead of N.
4. **`WeightedRoundRobin` rebuilt the expanded list every call.**
   `expand_node_list/2` ran `List.duplicate/2` per selection; for
   high weights the expanded list dominated allocation. Fix: cache
   the expanded list in `:persistent_term` keyed by the load-balancer
   name and the running node-list tuple. Topology change invalidates;
   steady-state hot path is `Enum.at/2` plus an atomic counter.

`LeastCpu` still has the largest per-call cost — its decode-per-node
path through `Cache.TermEncoder` is unchanged. A future pass could
move `NodeCpuCache` to direct `:persistent_term` storage (skip the
encoder) at the cost of giving up the test sandbox swap.

## Caveats

- Single-host benchmark — does not capture `:pg` membership churn or
  `:erpc` round-trip cost.
- M1 Max is a fast machine; absolute numbers will differ on
  production hardware, but ratios should hold.
- `LeastCpu` results assume a warm `NodeCpuCache`. Cache misses fall
  back to a 50% default and would not change the per-call cost.
