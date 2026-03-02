---
auto_execution_mode: 0
description: Review code changes for bugs, security issues, and improvements
---

You are a senior Elixir engineer performing a thorough code review on `rpc_load_balancer` — a standalone Elixir library that provides RPC wrappers around `:erpc` and a distributed node load balancer built on `:pg`.

Before reviewing any code, read `AGENTS.md` and all files in `.windsurf/rules/`.

---

# STEP 1: Gather Context

Run `gh pr view --json baseRefName,headRefName,title,body` to understand the PR context. Then run `gh pr diff` to see the actual changes. If the diff is large, focus on the most critical files first.

# STEP 2: Review Focus Areas

Find all potential bugs and code improvements. Focus on:

1. Logic errors and incorrect behavior
2. Edge cases that aren't handled
3. Nil reference issues (use `is_nil/1` guard, never `=== nil`)
4. Race conditions or concurrency issues (especially around `:pg`, ETS, and GenServer state)
5. Incorrect `:erpc` error handling or missing error cases
6. Cache correctness (ETS key collisions, stale algorithm/counter state, missing cache invalidation)
7. Load balancer fairness and correctness (node selection, round-robin counter overflow, `:pg` membership drift)
8. `@spec` accuracy — typespecs must match actual return values
9. **Violations of existing code patterns or conventions** (see full reference below)

# STEP 3: Review Guidelines

1. If exploring the codebase, call multiple tools in parallel for efficiency.
2. If you find any pre-existing bugs, report those too.
3. Do NOT report issues that are speculative or low-confidence. All conclusions must be based on a complete understanding of the codebase.
4. When reporting issues, reference the specific rule or convention being violated.

---

# PROJECT OVERVIEW

## What This Library Does
- **`RpcLoadBalancer`** — wraps `:erpc.call/5` and `:erpc.cast/4` with `ErrorMessage`-based error handling
- **`RpcLoadBalancer.LoadBalancer`** — GenServer that registers nodes via `:pg` process groups, supports pluggable selection algorithms
- **`RpcLoadBalancer.LoadBalancer.SelectionAlgorithm`** — behaviour for node selection, with `Random` and `RoundRobin` implementations
- **ETS caches** via `elixir_cache` — `AlgorithmCache` stores algorithm modules, `RoundRobinCounterCache` stores round-robin counters

## Dependencies
- `error_message` — structured error tuples
- `elixir_cache` — ETS-based caching (provides `Cache` module — never alias `RpcLoadBalancer.X` as `Cache`)
- `castore` — CA certificates
- Dev/test: `credo`, `blitz_credo_checks`, `excoveralls`, `dialyxir`, `ex_doc`

## Module Structure
```
lib/rpc_load_balancer/
├── application.ex                          # Starts Pg + Cache children
├── rpc_load_balancer.ex                    # RpcLoadBalancer — call/5, cast/4
├── load_balancer.ex                        # GenServer — start_link, select_node, get_members
└── load_balancer/
    ├── pg.ex                               # :pg wrapper
    ├── algorithm_cache.ex                  # Cache for selection algorithm modules
    ├── round_robin_counter_cache.ex        # Cache for round-robin counters
    ├── selection_algorithm.ex              # Behaviour + algorithm registry
    └── selection_algorithm/
        ├── random.ex                       # Random selection
        └── round_robin.ex                  # Round-robin selection with ETS counter
```

---

# CONVENTIONS REFERENCE

## 1. Elixir Code Conventions (always enforced)

### Strict Equality
- Use `===` instead of `==`
- Use `!==` instead of `!=`

### Nil Checks
- Use `is_nil(value)` instead of `value === nil`
- Use `not is_nil(value)` instead of `value !== nil`

### Empty Collections
- Use `Enum.empty?(list)` instead of `length(list) === 0` or `list === []`

### Pipe Operator
- Only use `|>` when there are at least 2 operations in the chain
- Always start pipe chains with a raw value: `a |> b() |> c()` not `b(a) |> c()`

### Function Naming
- Predicate functions use `?` suffix: `valid?/1`, `active?/1`
- Reserve `is_` prefix for guard clauses only
- Do not use 1-2 letter acronym variable names

### Assertions in Tests
- Use `refute` instead of `assert !` or `assert not`
- Use `is_nil/1` guard in assertions

### Atoms vs Strings
- Never mix atoms and strings for the same key access
- If data comes as strings, keep it as strings; fix upstream if needed

### Module Aliases
- Do not alias modules that would conflict with library modules (e.g., don't alias `RpcLoadBalancer.X` as `Cache` since `elixir_cache` provides `Cache`)
- Do not alias modules that are already short

### Comments
- Do not write comments unless the code is genuinely unusual
- Do not add explanatory comments for straightforward operations

---

## 2. Error Handling

### ErrorMessage Library
Use the `ErrorMessage` library (from `error_message` hex package) for all structured errors. Do **not** alias it — use `ErrorMessage` directly.

### Return Types
Public functions must return:
- `{:ok, result}` for success
- `{:error, ErrorMessage.t()}` for errors
- `:ok` for void success operations

### Error Chaining with `with`
```elixir
def process(params) do
  with {:ok, validated} <- validate(params),
       {:ok, result} <- execute(validated) do
    {:ok, result}
  end
end
```
The `with` block automatically propagates `{:error, _}` tuples — do not add redundant `else` clauses unless transforming errors.

### Flatten Nested Case Statements
When `case` statements are nested 2+ levels deep and error branches share the same handling, flatten them into `with`. Do **not** use `with` when different error branches need distinct handling or when there is only one `case` level.

### Bug Fixing
- Always fix the root cause, not symptoms
- Never apply downstream patches for upstream issues

---

## 3. GenServer Patterns

### Initialization
**Always** use `handle_continue/2` for initialization work instead of blocking in `init/1`:
```elixir
def init(opts) do
  {:ok, %{opts: opts}, {:continue, :initialize}}
end

def handle_continue(:initialize, state) do
  {:noreply, do_initialization(state)}
end
```

### ETS for Read-Heavy State
This library uses `elixir_cache` (ETS adapter) for algorithm and counter storage with `read_concurrency: true` and `write_concurrency: true`.

### Supervision
GenServers and caches are started in `RpcLoadBalancer.Application`:
```elixir
children = [
  RpcLoadBalancer.LoadBalancer.Pg,
  {Cache, [AlgorithmCache, RoundRobinCounterCache]}
]
```

---

## 4. Behaviour Pattern

The `SelectionAlgorithm` behaviour defines the contract for node selection:
```elixir
@callback choose_from_nodes(load_balancer_name(), [String.t() | atom()]) :: node()
```

Current implementations:
- `SelectionAlgorithm.Random` — `Enum.random/1`
- `SelectionAlgorithm.RoundRobin` — ETS counter with modular arithmetic, auto-resets at 10M

When adding new algorithms, implement the `SelectionAlgorithm` behaviour.

---

## 5. Testing and Code Quality

After completing code changes:
1. Run `mix test`
2. Run `mix credo --strict`
3. Run `mix dialyzer`

Tests should cover happy paths, edge cases, and error conditions.

---

# REVIEW CHECKLIST

When reviewing each changed file, verify against this checklist:

### For ALL Elixir files:
- [ ] Uses `===`/`!==` instead of `==`/`!=`
- [ ] Uses `is_nil/1` instead of `=== nil`
- [ ] Uses `Enum.empty?/1` instead of `length(list) === 0`
- [ ] Pipe chains start with raw values and have 2+ operations
- [ ] Predicate functions use `?` suffix, `is_` only in guards
- [ ] No 1-2 letter acronym variable names
- [ ] No unnecessary comments
- [ ] No mixing of atom and string keys

### For RPC wrapper functions (`RpcLoadBalancer`):
- [ ] All `:erpc` errors are rescued and mapped to `ErrorMessage` structs
- [ ] Return type is `{:ok, result} | {:error, ErrorMessage.t()}` or `:ok | {:error, ErrorMessage.t()}`
- [ ] `@spec` matches actual return shape
- [ ] Timeout is configurable with a sensible default

### For load balancer / GenServer files:
- [ ] Uses `handle_continue/2` for async init work (if any)
- [ ] `:pg` group joins/leaves are correct
- [ ] Node filtering logic handles edge cases (empty list, no matching nodes)
- [ ] `select_node/1` handles all error branches from `get_members/1` and `get_algorithm/1`

### For selection algorithm implementations:
- [ ] Implements `@behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm`
- [ ] Uses `@impl true` on callback functions
- [ ] Handles empty node list edge case
- [ ] Round-robin counter overflow is handled

### For cache modules:
- [ ] Uses `elixir_cache` (`use Cache`) — no raw `:ets` calls unless necessary for atomic operations (e.g., `update_counter`)
- [ ] `sandbox?: Mix.env() === :test` for test isolation
- [ ] Cache keys are unique and namespaced to avoid collisions across load balancer instances

### For typespecs:
- [ ] All public functions have `@spec`
- [ ] Types use `ErrorMessage.t_res(type)` for ok/error tuples where appropriate
- [ ] `node()`, `module()`, `atom()` types are used correctly

### For test files:
- [ ] Uses `refute` instead of `assert !`
- [ ] Uses `===`/`!==` for assertions
- [ ] No `Application.put_env` in tests
- [ ] No `Mix.env()` at runtime (only at compile time)
