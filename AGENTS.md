# AGENTS.md — rpc_load_balancer

Open-source Elixir library (Hex: `rpc_load_balancer`). Distributed RPC over `:erpc` with a `:pg`-backed load balancer and pluggable node-selection algorithms. Not an umbrella, not Phoenix, no database.

## Layout

```
lib/rpc_load_balancer.ex                      public API, per-instance Supervisor, `use` macro
lib/rpc_load_balancer/
  application.ex                              :pg scope + VM-wide Cache supervisor
  config.ex                                   app-env reader (call_directly?, retry?, retry_count, excluded_node_patterns)
  retry.ex                                    Retry.with_retry/2 (no-route backoff, :infinity supported)
  node_filter.ex                              NodeFilter.matches?/2,3 (substring/regex + excluded_node_patterns)
  metrics.ex                                  Telemetry.Metrics definitions
  load_balancer.ex                            GenServer: joins :pg, monitors membership, drains on terminate
  load_balancer/
    selection_algorithm.ex                    behaviour + dispatch layer + selection telemetry
    selection_algorithm/*.ex                  Random, RoundRobin, WeightedRoundRobin, LeastConnections,
                                              PowerOfTwo, HashRing, LeastCpu (+ least_cpu/poller.ex), CallDirect
    *_cache.ex                                elixir_cache-backed stores (see storage table in docs/explanation/architecture.md)
    drainer.ex, index_registry.ex, pg.ex
docs/                                         Diátaxis docs (hexdocs extras — keep mix.exs `docs/0` in sync)
bench/                                        Benchee scripts + bench/README.md (results + optimisation writeup)
skills/                                       elixir_skills SKILL.md shipped to consumers
test/                                         ExUnit; test/support/cache_case.ex for cache sandboxing
```

## Commands

```bash
mix test                      # whole suite; single node, no cluster needed
mix test test/path_test.exs:42
mix credo --strict
mix dialyzer                  # MIX_ENV=test; PLTs cached in .dialyzer/
mix docs                      # builds doc/ (gitignored)
MIX_ENV=dev mix run bench/select_node_bench.exs
```

Warnings are errors. Never run `mix format` unless asked.

## Conventions

- Style: `===`/`!==` over `==`/`!=`; `is_nil/1` over `== nil`; predicates end in `?` (`is_` only for guards); pipes start with a raw value and have ≥ 2 steps; no single-letter/acronym variable names; comments only when the logic is non-obvious; `Logger` messages prefixed with `#{__MODULE__}:` and values via `inspect/1`.
- Errors are `{:ok, _} | {:error, %ErrorMessage{}}`; map `:erpc` failures to `request_timeout` / `service_unavailable` / `bad_request`.
- No `Application.put_env` in tests; use `call_directly?:` / `retry?:` per-call options or `algorithm_opts` (e.g. `cpu_sampler`, `poll_startup_jitter: 0`) instead.
- Load balancers in tests: `start_supervised!({RpcLoadBalancer, name: unique, selection_algorithm: ...})` — `start_link/1` returns after the `:pg` join, no sleeps.
- Hot path (`choose_from_nodes/3`) must not go through `Cache.get/1` (telemetry span per read). Use the raw accessors (`CounterCache.get_node_count/2`, `HashRingCache.get_ring/1`, `NodeCpuCache.get_cpu/1`) or add one. Benchmark before/after with `bench/`.
- `:persistent_term` only for write-once state (algorithm config at `init/2`). Anything rewritten on `on_node_change/2` goes in an ETS-backed cache. Reason: PT writes trigger global GC.
- New built-in algorithm: implement the behaviour, add to `@known_algorithms` in `application.ex` if it has `caches/0`, add a bench entry in `bench/support.exs`, a how-to in `docs/how-to/`, a row in the README/reference tables, and a CHANGELOG entry.
- Public API changes: update the moduledoc, `docs/reference/load_balancer.md`, `docs/how-to/*` that touch it, `README.md`, and `CHANGELOG.md` in the same PR. Docs live in three places (moduledocs, `docs/`, README) — keep them saying the same thing.

## Commits & PRs

- Conventional commits: `feat:`, `fix:`, `docs:`, `chore:`, `perf:`, `test:`, `refactor:`. Reference the PR number in CHANGELOG entries.
- No AI attribution footers. Squash/rebase only — no merge commits.
- Bump `version` in `mix.exs` and add a `## x.y.z` CHANGELOG section in a `chore: release x.y.z` commit.
