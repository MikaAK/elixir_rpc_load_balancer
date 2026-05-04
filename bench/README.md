# Benchmarks

Benchee scripts that measure the cost of `choose_from_nodes/3` for every
selection algorithm in isolation — no `:pg` lookups, no network. The
synthetic node pool lets us scale cluster size up to 32 nodes while
keeping every other variable constant.

## Running

```sh
mix deps.get
MIX_ENV=dev mix run bench/select_node_bench.exs   # node-count sweep
MIX_ENV=dev mix run bench/contention_bench.exs    # parallel: 8
```

## What gets measured

| Script | Purpose |
|---|---|
| `select_node_bench.exs` | Pure single-process `choose_from_nodes/3` cost across 2 / 8 / 32 nodes. Captures wall time, allocations, reductions. |
| `contention_bench.exs` | Same call run with `parallel: 8` to surface ETS / lock-table contention. |

`bench/support.exs` boots the application, starts one load balancer per
algorithm, and pre-warms `CounterCache` and `NodeCpuCache` so we measure
steady-state behavior, not first-touch lazy-initialization. The
`LeastCpu` poller is configured with a 10-minute jitter and a fixed CPU
sampler so it never fires during the benchmark.

## Results — Apple M1 Max, Elixir 1.19.5 / OTP 28.3.3

### `select_node` — single process, 8 nodes (representative cluster size)

| Algorithm | ips | avg | median | p99 | memory | reductions |
|---|---:|---:|---:|---:|---:|---:|
| `CallDirect` | 23.39 M | 0.04 μs | 0.04 μs | 0.08 μs | 0 KB | 2 |
| `Random` | 8.88 M | 0.11 μs | 0.08 μs | 0.13 μs | 0.34 KB | 46 |
| `RoundRobin` | 1.24 M | 0.81 μs | 0.71 μs | 0.96 μs | 1.05 KB | 133 |
| `PowerOfTwo` | 391 K | 2.56 μs | 2.33 μs | 4.25 μs | 4.83 KB | 439 |
| `WeightedRoundRobin` | 359 K | 2.78 μs | 2.38 μs | 6.46 μs | 2.16 KB | 287 |
| `LeastConnections` | 170 K | 5.87 μs | 5.54 μs | 13.42 μs | 9.01 KB | 956 |
| `LeastCpu` | 57.5 K | 17.40 μs | 14.50 μs | 77.54 μs | 8.66 KB | 776 |
| `HashRing` | 34.8 K | 28.73 μs | 27.25 μs | 50.63 μs | 1.32 KB | 284 |

### Scaling with cluster size (avg µs)

| Algorithm | 2 nodes | 8 nodes | 32 nodes | Notes |
|---|---:|---:|---:|---|
| `CallDirect` | 0.04 | 0.04 | 0.04 | constant — never touches the node list |
| `Random` | 0.12 | 0.11 | 0.13 | constant — `Enum.random/1` on a list |
| `RoundRobin` | 0.81 | 0.81 | 0.84 | constant — atomic counter + `Enum.at/2` |
| `PowerOfTwo` | 2.08 | 2.56 | 3.24 | sub-linear — picks 2 random, ETS lookup × 2 |
| `WeightedRoundRobin` | 2.95 | 2.78 | 3.54 | sub-linear — `List.duplicate` per call |
| `HashRing` | 28.56 | 28.73 | 28.60 | constant — `libring` lookup on cached ring |
| `LeastConnections` | 1.85 | 5.87 | 21.49 | **linear** — ETS counter read per node |
| `LeastCpu` | 6.12 | 17.40 | 63.82 | **linear** — `PersistentTerm` read per node |

### Parallel contention — 8 schedulers, 8 nodes

| Algorithm | single avg | parallel avg | slowdown | p99 |
|---|---:|---:|---:|---:|
| `CallDirect` | 0.04 μs | 0.02 μs | — (faster) | 0.05 μs |
| `Random` | 0.11 μs | 0.14 μs | 1.3× | 0.42 μs |
| `RoundRobin` | 0.81 μs | 1.52 μs | 1.9× | 4.04 μs |
| `PowerOfTwo` | 2.56 μs | 4.29 μs | 1.7× | 17.79 μs |
| `WeightedRoundRobin` | 2.78 μs | 4.41 μs | 1.6× | 20.54 μs |
| `LeastConnections` | 5.87 μs | 10.35 μs | 1.8× | 44.71 μs |
| `LeastCpu` | 17.40 μs | 25.02 μs | 1.4× | 141.33 μs |
| `HashRing` | 28.73 μs | **190.59 μs** | **6.6×** | 843.46 μs |

## Bottlenecks identified

1. **`HashRing` serializes under read contention.** The ring is cached
   in an ETS table with a single owner — every parallel reader waits on
   that table. Single-threaded cost is already the highest, and the
   parallel slowdown is by far the worst (6.6×). Candidates to fix:
   move the ring to `:persistent_term`, or keep ETS but enable
   `read_concurrency: true` if it isn't already.
2. **`LeastConnections` and `LeastCpu` scale linearly with cluster size.**
   Both walk every node on every selection. At 32 nodes they cost
   21 μs and 64 μs respectively — 3× and 11× more than `PowerOfTwo` on
   the same cluster while delivering similar load distribution.
   `PowerOfTwo` is the better default once the cluster grows past ~8
   nodes.
3. **`LeastConnections` allocates 34 KB per call at 32 nodes.** The
   `Enum.map` → `Enum.min_by` → tuple-of-tuples chain rebuilds a fresh
   list for every selection. Switching to a single `Enum.reduce/3` that
   tracks `{best_node, best_count}` would drop the allocation to a
   single tuple.
4. **`WeightedRoundRobin` rebuilds the expanded node list per call.**
   `expand_node_list/2` runs `List.duplicate/2` on every selection;
   for high weights the expanded list dominates allocation. Caching
   the expanded list (invalidated on `on_node_change`) would make this
   constant-time.
5. **`Random` allocates 0.34 KB per call.** `Enum.random/1` traverses
   the list to find its length. For large clusters,
   `Enum.random/1` on a tuple, or pre-converting the node list to a
   tuple in cache, would eliminate this.

## Caveats

- Single-host benchmark — does not capture `:pg` membership churn or
  `:erpc` round-trip cost.
- M1 Max is a fast machine; absolute numbers will differ on
  production hardware, but ratios should hold.
- `LeastCpu` results assume a warm `NodeCpuCache`. Cache misses fall
  back to a 50% default and would not change the per-call cost.
