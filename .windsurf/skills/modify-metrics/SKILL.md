---
name: modify-metrics
description: "Telemetry and metrics patterns for the CheddarFlow project. TRIGGER when: writing or modifying telemetry events, metrics definitions, CFXMetrics modules, or monitoring-related code. Also trigger when adding :telemetry.execute or :telemetry.span calls, or working with Prometheus/Grafana metric exports. DO NOT TRIGGER when: working with code that doesn't involve observability or metrics."
---

# Metrics & Telemetry

Uses Erlang's `:telemetry` with custom metric definitions published to Grafana via Prometheus.

## CFXMetrics

`cfx_metrics` (`apps/cfx_metrics/`) aggregates metrics from domain-specific modules:

| Module | Domain |
|--------|--------|
| `CFXMetrics.Alerts` | Alert system |
| `CFXMetrics.DarkPoolEventsProcessor` | Dark pool pipeline |
| `CFXMetrics.FeedServers` | Feed server operations |
| `CFXMetrics.LastSymbolPricePoller` | Price polling |
| `CFXMetrics.MarketStatus` | Market status changes |
| `CFXMetrics.OptionsChainPoller` | Options chain scraping |
| `CFXMetrics.OptionChainPollScheduler` | Poll scheduling |
| `CFXMetrics.OptionsEventsProcessor` | Options pipeline |
| `CFXMetrics.SubscriptionWebhooks.Controller` | Stripe webhooks |
| `CFXMetrics.GammaExposure` | Gamma exposure |
| `CFXMetrics.RpcMetrics` | Cross-node RPC |
| `Cache.Metrics` | Cache hit/miss/error (from `elixir_cache`) |

## Configuration

```elixir
config :cfx_metrics, enabled?: false, exporter_opts: [enabled?: false, opts: []]  # dev/test
config :cfx_metrics, enabled?: true, exporter_opts: [enabled?: true]               # prod
```

## Per-App Telemetry Modules

Each release app has a `Telemetry` module in its supervision tree:
`CFXWeb.Telemetry`, `CFXBgProcessor.Telemetry`, `OptionsEventsProcessor.Telemetry`, `DarkPoolEventsProcessor.Telemetry`, `OptionsFeed.Telemetry`, `DiscordService.Telemetry`

## Telemetry Event Patterns

**Span-based timing:**
```elixir
:telemetry.span([:cfx, :feed_servers, :get_state], %{adapter: adapter}, fn ->
  result = do_work()
  {result, %{adapter: adapter}}
end)
```

**Counter events:**
```elixir
:telemetry.execute([:elixir_cache, :cache, :get, :miss], %{count: 1}, %{cache_name: cache_name})
```

**RPC metrics** wrap all cross-node calls:
```elixir
RpcMetrics.span_call(module, fun, node, fn ->
  :erpc.call(node, module, fun, args, timeout)
end)
```

## Adding New Metrics

1. Define in appropriate `CFXMetrics.*` module
2. Add telemetry events using `:telemetry.execute/3` or `:telemetry.span/3`
3. Ensure included in `CFXMetrics.metrics/0`
4. Release app Telemetry module picks up automatically

## Logging

Structured logging with `LogfmtEx`:
```elixir
config :logger, :console, format: {LogfmtEx, :format}, metadata: [:application, :client_ip, :feed_adapter]
```

Log aggregation via Loki in production with Grafana dashboards.
