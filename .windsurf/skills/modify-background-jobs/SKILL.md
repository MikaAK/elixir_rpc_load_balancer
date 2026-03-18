---
name: modify-background-jobs
description: "Oban background job patterns for the CheddarFlow project. TRIGGER when: writing or modifying Oban workers, background jobs, cron schedules, job queue configuration, or any code that enqueues or processes Oban jobs. Also trigger when working with Schemas.JobsRepo for job-related queries. DO NOT TRIGGER when: working with code that doesn't involve background job processing."
---

# Background Jobs (Oban)

The project uses Oban for background job processing with a dedicated PostgreSQL database (`Schemas.JobsRepo`).

## Oban Instances

| Instance | Release | Queues | Purpose |
|----------|---------|--------|---------|
| `CFXBgProcessor.Oban` | `cfx_bg_processor` | Various (price polling, chain scraping, alerting, mailer) | Main background processor |
| `OptionsEventsProcessor.Oban` | `options_events_processor` | `options_trades_events`, `unusual_volume_daily_poller` | Options event ingestion |
| `DarkPoolEventsProcessor.Oban` | `dark_pool_events_processor` | `dark_lit_trades_events` | Dark pool event ingestion |
| `OptionsChainProcessor.Oban` | `options_chain_processor` | Options chain jobs | Dedicated chain processing |
| `DiscordService.Oban` | `discord_service` | Discord-related jobs | Discord bot operations |

## Key Conventions

- **All Oban instances use `Schemas.JobsRepo`** — never the main `Schemas.Repo`
- **Named instances**: Each non-default instance needs `name:` config (e.g., `name: DarkPoolEventsProcessor.Oban`)
- **Peer configuration**: `peer: false` for instances that shouldn't participate in leadership election
- **Config providers**: `cfx_bg_processor` and `options_chain_processor` use runtime config providers

## Cron Jobs

```elixir
config :options_events_processor, Oban,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"*/5 9-16 * * MON-FRI", OptionsEventsProcessor.UnusualVolumeDailyPoller}
     ],
     timezone: "America/New_York"}
  ]
```

Market hours (9:30 AM - 4:00 PM ET, Monday-Friday) are relevant for most cron schedules.

## Worker Pattern

```elixir
defmodule CFXBgProcessor.MyWorker do
  use Oban.Worker,
    queue: :my_queue,
    max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    :ok
  end
end
```

## Adding New Background Jobs

1. Define worker in the appropriate app
2. Add queue to Oban config in `config/config.exs` (or app config)
3. For cron jobs, add to `Oban.Plugins.Cron` with timezone
4. Enqueue with `Oban.insert/1` or `Oban.insert!/1`
5. For node-specific jobs, configure the queue only on that release's Oban instance

## Testing

- Use `Oban.Testing` helpers for asserting job enqueuing
- Test workers by calling `perform/1` directly with a constructed `%Oban.Job{}`
- Test env sets `queues: []` and `peer: false` to prevent execution
