---
name: modify-ecto-schemas
description: "Ecto schema, migration, and database patterns for the CheddarFlow project. TRIGGER when: writing or modifying Ecto schemas, changesets, migrations, database queries, context modules, or any code in the schemas app. Also trigger when creating new database tables, adding indexes, working with EctoShorts, QueryBuilder, TimescaleDB, or FactoryEx factories. DO NOT TRIGGER when: working with code that doesn't touch the database layer."
---

# Ecto Schemas & Database Patterns

## Repo Configuration

- **`Schemas.Repo`** — Main PostgreSQL + TimescaleDB database. Holds user data, trades, options, entitlements.
- **`Schemas.JobsRepo`** — Isolated PostgreSQL database for Oban job queues only.

Pool sizes are tuned per-release in `config/runtime.exs`:
```elixir
release_repo_config = %{
  "cfx_web" => [pool_size: 20],
  "options_feed" => [pool_size: 40, prepare: :unnamed],
  "dark_pool_lit_feed" => [pool_size: 20, prepare: :unnamed],
}
```

Feed nodes use `prepare: :unnamed` to avoid prepared statement conflicts.

## Schema Organization

Schemas are grouped by domain under `apps/schemas/lib/schemas/`:

```
schemas/
├── accounts/          # User accounts, profiles, settings
├── accounts.ex        # Context module — public API for accounts
├── api/               # API keys, rate limits
├── agreements/        # User agreements
├── companies/         # Company data
├── dark_pool_lit/     # Dark pool and lit trade schemas
├── discord/           # Discord integration schemas
├── entitlements/      # User subscription entitlements
├── gamma_exposure.ex  # Gamma exposure data
├── options/           # Options trades, contracts, chains
├── options.ex         # Context module — public API for options
├── power_alerts/      # Power alert configurations
├── prices/            # Price data
├── symbols/           # Trading symbols
├── query_builder.ex   # Reusable query building helpers
├── timescale/         # TimescaleDB-specific utilities
└── types/             # Custom Ecto types
```

## Context Module Pattern

Each domain has a context module providing the public API:

```elixir
defmodule Schemas.Accounts do
  def get_user(id), do: ...
  def create_user(attrs), do: ...
  def update_user(user, attrs), do: ...
end
```

These use `EctoShorts.Actions` for common CRUD operations.

## Key Conventions

- **`EctoShorts`** is configured with `Schemas.Repo` as the default repo
- **`FactoryEx`** for test data factories — define in `test/support/`
- **TimescaleDB hypertables** for time-series data (options trades) with retention policies in `config/prod.exs`
- **Custom Ecto types** in `Schemas.Types.*`
- **`Schemas.QueryBuilder`** for reusable query composition (filtering, sorting, pagination)
- **ShortUUID** for some primary keys via `ecto_shortuuid`

## Migrations

- Main DB: `apps/schemas/priv/repo/migrations/`
- Jobs DB: `apps/schemas/priv/jobs_repo/migrations/`
- Always add appropriate indexes for columns in WHERE, JOIN, and ORDER BY clauses
- For TimescaleDB hypertables, use `Timescale.Migration` helpers
- Run all migrations: `mix ecto.migrate_all` (aliased as `mix schemas.migrate_all`)
- Always write migrations when creating new schemas

## Testing

- Run from schemas app: `cd apps/schemas && mix test`
- Use `FactoryEx` for all test data — never `Repo.insert!`
- `propcheck` available for property-based testing
