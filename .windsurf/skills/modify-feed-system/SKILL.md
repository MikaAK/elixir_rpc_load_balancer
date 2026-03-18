---
name: modify-feed-system
description: "Feed system patterns for the CheddarFlow project. TRIGGER when: writing or modifying feed server code, feed adapters, SharedFeedUtils, FeedServer, FeedSupervisor, or any real-time data streaming components. Also trigger when working with ETS-backed feed state, feed routing via CFXRpc, or Absinthe subscription resolvers that read feed data. DO NOT TRIGGER when: working with code unrelated to real-time data feeds."
---

# Feed System Architecture

The feed system is the core real-time data delivery mechanism. It manages per-user or per-query GenServer processes that maintain filtered, aggregated trading data and push updates via Absinthe GraphQL subscriptions.

## Core Abstractions (in `shared_feed_utils`)

- **`SharedFeedUtils.Feed`** — Struct representing a feed's full state: adapter, id, filters, topic, data, timeout, etc.
- **`SharedFeedUtils.FeedServer`** — GenServer maintaining a `Feed` in ETS for high-performance reads, subscribes to PubSub, processes events through adapter callbacks, pushes updates to WebSocket subscribers.
- **`SharedFeedUtils.FeedSupervisor`** — DynamicSupervisor managing FeedServer processes. Uses `Registry` for unique naming via `via_tuple/2`.
- **`SharedFeedUtils.Supervisor`** — Top-level supervisor starting Registry + FeedSupervisor + default permanent servers.

## Feed Adapter Pattern

```elixir
defmodule OptionsFeed.OptionsFeedAdapter do
  @behaviour SharedFeedUtils.FeedAdapter

  def name, do: __MODULE__
  def pubsub_module, do: OptionsEventsProcessor.PubSub
  def pubsub_topics, do: ["options_flow_events"]
  def process_event(feed, event), do: ...
  def build_initial_state(feed), do: ...
end
```

## Supervision Tree

```
SharedFeedUtils.Supervisor (per adapter)
├── Registry (unique names: {adapter}.FeedRegistry)
├── SharedFeedUtils.FeedSupervisor (DynamicSupervisor)
│   ├── FeedServer (permanent: ask-side filter)
│   ├── FeedServer (permanent: all-sides filter)
│   └── FeedServer (temporary: per-user query, times out)
└── ... default permanent servers
```

## Feed Server Lifecycle

1. **Permanent servers** start with the application and never time out — common filter configurations
2. **Temporary servers** started on-demand via `FeedSupervisor.get_or_start_server!/2`, time out after inactivity
3. State stored in **named ETS table** for lock-free reads from subscription resolvers
4. FeedServer subscribes to PubSub on init, processes events via `handle_info`
5. State rebuilt at market open (9:31 ET) and after open interest data arrives (10:05 ET)

## ETS State Storage

- Table name: `:"feed_state_#{adapter}_#{id}"`
- Options: `[:protected, :set, :named_table, read_concurrency: true]`
- Read via `FeedServer.get_state/2` — no GenServer call needed

## Distributed Routing

Feed apps run on dedicated nodes. Web app routes via `CFXRpc`:

```elixir
CFXRpc.route_to_node("options_feed", feed_id, SharedFeedUtils.FeedSupervisor, :get_or_start_server!, [feed])
```

- `route_to_node/5` uses consistent hashing on `feed_id`
- `call_on_random_node/4` picks any matching node
- Dev/test with `call_directly?: true` calls locally

## Existing Feed Adapters

| Adapter | Feed App | PubSub Source | Data Type |
|---------|----------|---------------|-----------|
| `OptionsFeed.OptionsFeedAdapter` | `options_feed` | `OptionsEventsProcessor.PubSub` | Options trades |
| `DarkPoolLitFeed.DarkPoolLitFeedAdapter` | `dark_pool_lit_feed` | `DarkPoolEventsProcessor.PubSub` | Dark pool/lit trades |
| `OptionsUnusualVolumeFeed.Adapter` | `options_unusual_volume_feed` | `OptionsEventsProcessor.PubSub` | Unusual volume |
| `GammaExposureFeed.Adapter` | `gamma_exposure_feed` | `CFXWeb.PubSub` | Gamma exposure |
| `DiscordService.FeedBot.*Adapter` | `discord_service` | Various | Discord alerts |

## Adding a New Feed Type

1. Create adapter implementing `SharedFeedUtils.FeedAdapter`
2. Define PubSub topics, event processing, and initial state building
3. Add `SharedFeedUtils.Supervisor` to the app's supervision tree
4. Configure `node_type` and `node_count`
5. Add RPC routing in `cfx_web` resolvers
6. Create Absinthe subscription reading from feed's ETS state
