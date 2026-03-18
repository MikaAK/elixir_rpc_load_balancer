---
name: modify-feature-flags
description: "Feature flag patterns for the CheddarFlow project. TRIGGER when: writing or modifying feature flag code, FunWithFlags usage, CFXFeatureFlags calls, or conditional feature enablement. Also trigger when adding new flags to config or checking flag state. DO NOT TRIGGER when: working with code that doesn't involve feature flags."
---

# Feature Flags

Managed via `FunWithFlags` with Ecto persistence, wrapped by `cfx_feature_flags`.

## CFXFeatureFlags API

```elixir
CFXFeatureFlags.enabled?(:my_flag)
CFXFeatureFlags.enable(:my_flag)
CFXFeatureFlags.disable(:my_flag)
CFXFeatureFlags.clear(:my_flag)
CFXFeatureFlags.all_flags()
CFXFeatureFlags.all_flag_names()
```

## Default Flags

Configured per environment, initialized on startup via `CFXFeatureFlags.initialize/1`:

```elixir
# config/config.exs (dev/test defaults)
config :cfx_feature_flags, :default_flags,
  symbol_price_polling: false,
  options_contract_polling: false,
  options_contract_expiry_scraping: false

# config/prod.exs
config :cfx_feature_flags, :default_flags,
  symbol_price_polling: true,
  options_contract_polling: false,
  options_contract_expiry_scraping: true
```

`initialize/1` will **not overwrite** already-persisted flags — only sets defaults for new flags.

## Persistence & Cache

- **Persistence**: `FunWithFlags.Store.Persistent.Ecto` backed by `Schemas.Repo` (prod only)
- **Cache**: In-process, 900s TTL in prod
- **Cache busting**: Via `Phoenix.PubSub` through `CFXWeb.PubSub` — propagates across cluster

## Adding a New Feature Flag

1. Add flag name and default to `:default_flags` in `config.exs` and `prod.exs`
2. Check with `CFXFeatureFlags.enabled?(:flag_name)`
3. Auto-initialized on next deploy via `CFXFeatureFlags.initialize/0`
4. Toggle at runtime: `CFXFeatureFlags.enable(:flag_name)`
