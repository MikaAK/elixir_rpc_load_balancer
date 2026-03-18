---
name: modify-event-processor
description: "GenStage pipeline patterns for the CheddarFlow project. TRIGGER when: writing or modifying GenStage pipelines, event processors, trade ingestion code, or any code in options_events_processor or dark_pool_events_processor apps. Also trigger when working with PipelineSupervisor, Producer/Consumer stages, or SSE ingestion. DO NOT TRIGGER when: working with code unrelated to event processing pipelines."
---

# Event Processors (GenStage Pipelines)

Event processors are GenStage pipelines that ingest external trading data and broadcast it to the cluster via PubSub.

## OptionsEventsProcessor

Ingests real-time options trades from TradeAlert API:

```
OptionsTradesEventsProducer (GenStage.Producer)
        │
        ▼
OptionsTradesValidatorProducerConsumer (GenStage.ProducerConsumer)
        │
        ▼
OptionsFlowConsumer (GenStage.Consumer)
        │
        ▼
CFXPubSub.options_events_broadcast/2 → OptionsEventsProcessor.PubSub
```

**Stages:**
- **Producer** — Receives trade events from TradeAlert via Oban job or direct API polling
- **ValidatorProducerConsumer** — Validates and normalizes trade data, filters invalid trades
- **Consumer** — Broadcasts validated events to PubSub topics (`"options_flow_events"`, `"contract_activity:<symbol>"`, etc.)

**Dev/test mode:** `OptionsFlowSimulatorProducer` generates fake trade data. Consumer subscribes to both validator and simulator.

## DarkPoolEventsProcessor

Ingests dark pool and lit trades from DxFeed SSE:

```
DxFeedSSEProducer(s) (multiple, partitioned by symbol chunks)
        │
        ▼
BackerQueueProducerConsumer (backpressure buffer)
        │
        ▼
DarkPoolFeedConsumer (GenStage.Consumer)
        │
        ▼
Phoenix.PubSub.broadcast → DarkPoolEventsProcessor.PubSub
```

**Key design:**
- **Multiple producers**: Symbols chunked into groups of 400, each with its own SSE producer
- **Backpressure queue**: `BackerQueueProducerConsumer` buffers SSE bursts
- **Conditional startup**: Only starts if `DarkPoolEventsProcessor.Config.enabled?()` is true
- **Symbol scraping**: On init, `DxFeedApi.SymbolScraper.scrape_and_cache_symbols/0` fetches symbol list

## Configuration

```elixir
config :dark_pool_events_processor, enabled?: false  # true in prod

config :options_events_processor, Oban,
  name: OptionsEventsProcessor.Oban,
  repo: Schemas.JobsRepo,
  queues: [options_trades_events: 1, unusual_volume_daily_poller: 1]
```

## Adding a New Event Processor

1. Create a new app under `apps/`
2. Define GenStage producer(s) for data ingestion
3. Add validation/transformation ProducerConsumer stages as needed
4. Create consumer broadcasting to a PubSub topic
5. Wrap stages in a `PipelineSupervisor`
6. Start pipeline supervisor in the application's supervision tree
7. Add cluster topology supervisor for distributed operation
8. Configure Oban instance if periodic jobs are needed
