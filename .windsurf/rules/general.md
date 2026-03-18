---
trigger: always_on
---

## Skill Routing

Before working on code in this project, you **must** read the relevant skill(s) from `.windsurf/skills/`. Each skill is a directory containing a `SKILL.md` file with domain-specific patterns, conventions, and requirements. Some skills also have a `references/` subdirectory with additional documentation to read when needed.

To read a skill, use the `skill` tool with the skill name (e.g., `modify-elixir-code`).

### Required skills by task type

| Task | Required Skill(s) |
|------|-------------------|
| Writing or modifying **any Elixir code** | `modify-elixir-code` (always read first) |
| Phoenix framework, LiveView, templates, routes, components | `modify-phoenix-code` |
| Ecto schemas, migrations, queries, database code | `modify-ecto-schemas` |
| GraphQL schemas, types, queries, mutations, subscriptions, resolvers | `modify-graphql` |
| API wrapper apps (`_api` suffix), external HTTP requests | `modify-api-wrapper` |
| Feed servers, feed adapters, SharedFeedUtils, real-time streaming | `modify-feed-system` |
| GenStage pipelines, event processors, trade ingestion | `modify-event-processor` |
| Oban workers, background jobs, cron schedules | `modify-background-jobs` |
| Caching (Redis, ETS, elixir_cache, cache apps) | `modify-caching` |
| Tests, test support modules, test configuration | `modify-tests` |
| Authentication, authorization, sessions, Auth0 | `modify-auth` |
| Cross-node RPC, libcluster, PubSub, distributed Erlang | `modify-distributed-cluster` |
| Feature flags, FunWithFlags | `modify-feature-flags` |
| Telemetry events, metrics, monitoring | `modify-metrics` |
| Deployment, OpenTofu, Ansible, CI/CD, releases | `modify-infrastructure` |
| Adding dependencies, creating apps, modifying mix.exs | `modify-dependencies` |

### Skill composition

Many tasks require multiple skills. For example:
- Creating a new Oban worker → `modify-elixir-code` + `modify-background-jobs` + `modify-tests`
- Adding a new GraphQL field → `modify-elixir-code` + `modify-graphql` + `modify-ecto-schemas`
- Adding a new feed type → `modify-elixir-code` + `modify-feed-system` + `modify-distributed-cluster`

**Always read `modify-elixir-code` first** when writing any Elixir code.

### AWS commands

When using AWS or any command that uses AWS (tofu, ansible):
- Always use `AWS_PROFILE=cheddarflow`
- Use `tofu` instead of `terraform`
- Use `--var-file prod.tfvars`

### Global coding standards

- Use `mix precommit` when done with all changes
- Warnings are errors — fix them
- Don't apply bug fixes that are patches — always fix the root cause
- Don't change behavior of existing code unless asked
- Don't add comments unless necessary
- Run tests after writing them

### Per-app context

Many apps have their own `AGENTS.md` with app-specific architecture, module layout, and conventions. When working on a specific app, read its `apps/<app>/AGENTS.md` if it exists. Apps with their own AGENTS.md:
`cfx_web`, `schemas`, `shared_feed_utils`, `shared_utils`, `cfx_bg_processor`, `options_events_processor`, `dark_pool_events_processor`, `options_feed`, `cfx_rpc`, `cfx_pub_sub`, `auth`, `stripe_api`

The root `AGENTS.md` contains the project overview, architecture diagram, deployment topology, and full app catalog — read it when you need project-wide context.

### Skill references

Some skills have a `references/` subdirectory with larger reference documents. These are loaded on demand — the SKILL.md will tell you when to read them. Current reference files:
- `modify-elixir-code/references/elixir-style-guide.md` — Full Elixir community style guide
- `modify-caching/references/elixir-cache-reference.md` — elixir_cache library API reference
