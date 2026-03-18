---
name: modify-caching
description: "Caching patterns for the CheddarFlow project. TRIGGER when: writing or modifying caching code involving Redis, ETS, elixir_cache, Cachex, or any of the _cache apps. Also trigger when working with RedisLock, Cache.Redis, Cache.ETS, or cache sandbox testing. DO NOT TRIGGER when: working with code that doesn't involve caching layers."
---

# Caching Patterns

## Cache Apps (`_cache` suffix)

Dedicated cache apps use the `elixir_cache` library:

| App | Backend | Name | Purpose |
|-----|---------|------|---------|
| `active_symbols_cache` | Redis (`Cache.Redis`) | `:active_symbols` | Currently traded symbols |
| `last_symbol_price_cache` | Redis (`Cache.Redis`) | `:last_symbol_price` | Latest price per symbol |
| `options_contract_expiry_cache` | Redis (`Cache.Redis`) | `:options_contract_expiry` | Contract expiration dates |
| `open_interest_cache` | ETS (`Cache.ETS`) | `:open_interest` | Open interest data (local-only) |

## elixir_cache Library Usage

For full library reference, read `references/elixir-cache-reference.md`.

Define a cache module:

```elixir
defmodule MyApp.MyCache do
  use Cache,
    adapter: Cache.Redis,  # or Cache.ETS
    name: :my_cache,
    sandbox?: Mix.env() === :test,
    opts: :my_app  # or keyword list, or {app, key}, or {M, F, A}
end
```

**API:**
- `MyCache.put(key, ttl \\ nil, value)` — store a value
- `MyCache.get(key)` — retrieve `{:ok, value}` or `{:ok, nil}` for miss
- `MyCache.delete(key)` — remove a key
- `MyCache.get_or_create(key, fn -> {:ok, value} end)` — get or compute and cache

**Adapters:**
- `Cache.Redis` — Redis-backed, cross-node accessible
- `Cache.ETS` — In-memory ETS, node-local, high performance

**ETS adapter options** (via NimbleOptions):
- `read_concurrency`, `write_concurrency`, `decentralized_counters` — boolean
- `type` — `:set`, `:bag`, `:duplicate_bag` (default `:set`)
- `compressed` — boolean
- `store_on_exit_path` — persist ETS to disk on exit and rehydrate on startup

**ETS-specific operations** (available when using `Cache.ETS` adapter):
- `MyCache.lookup/1`, `MyCache.insert_raw/1`, `MyCache.member/1`
- `MyCache.match_pattern/1`, `MyCache.select/1`, `MyCache.tab2list/0`
- `MyCache.update_counter/2`, `MyCache.foldl/2`, etc.

**Sandbox support**: Use `sandbox?: true` in test — keys are prefixed with sandbox ID for async-safe isolation via `Cache.SandboxRegistry`.

## Redis Configuration

All Redis-backed services connect to the same Redis instance:
```elixir
config :auth, Auth.Sessions.SessionCache, uri: redis_uri
config :redis_lock, Redix, uri: redis_uri
config :last_symbol_price_cache, Redix, uri: redis_uri
config :options_contract_expiry_cache, Redix, uri: redis_uri
config :active_symbols_cache, Redix, uri: redis_uri
```

## Web App Caches (Cachex/ETS)

`cfx_web` in-process caches:
- **`CFXWeb.TradesCache`** — Cached trade data
- **`CFXWeb.GammaExposureCache`** — Gamma exposure data
- **`CFXWeb.UserCache`** — User data

Started as children of `CFXWeb.Application`, local to web node.

## Feed Server ETS Caches

- Table per feed server: `:"feed_state_#{adapter}_#{id}"`
- Options: `[:protected, :set, :named_table, read_concurrency: true]`
- Written by FeedServer GenServer, read by subscription resolvers without GenServer calls

## Distributed Locking (RedisLock)

```elixir
RedisLock.acquire("lock_key", ttl: 30_000, fn ->
  # Critical section
end)
```

## Design Decisions

- **Redis** for cross-node caches (prices, sessions, contracts)
- **ETS** for node-local hot data (feed state, open interest) — avoids network overhead
- **Separate cache apps** for fine-grained dependency management
- **`elixir_cache`** provides unified `use Cache` interface with adapter pattern, term encoding, telemetry, sandbox support

## Adding a New Cache

1. Redis-backed: Create `_cache` app, `use Cache, adapter: Cache.Redis, name: :my_cache, opts: ...`
2. ETS-backed: `use Cache, adapter: Cache.ETS, name: :my_cache, opts: [read_concurrency: true]`
3. Add Redis URI config in `config/runtime.exs` if Redis-backed
4. Start cache module in consuming app's supervision tree
5. For test sandboxing: Use `sandbox?: true`
