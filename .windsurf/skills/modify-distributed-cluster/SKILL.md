---
name: modify-distributed-cluster
description: "Distributed cluster patterns for the CheddarFlow project. TRIGGER when: writing or modifying code involving cross-node communication, CFXRpc, libcluster, Phoenix.PubSub broadcasting, distributed Erlang, or node routing. Also trigger when working with SharedUtils.Cluster, CFXPubSub, or any code that needs to handle dev/test vs prod cluster differences. DO NOT TRIGGER when: working with single-node code that doesn't involve distribution."
---

# Distributed Cluster Architecture

CheddarFlow runs as a distributed Erlang cluster with 11+ nodes communicating via `Phoenix.PubSub` and `:erpc`.

## Cluster Formation

- **Production**: Auto-discover via `libcluster` using `Cluster.Strategy.EC2Tag` with tag `Group: "CFX Backend"`
- **Dev/Test**: Clustering disabled — `cfx_rpc` config `call_directly?: true` makes RPC calls local
- Each release app joining the cluster starts `SharedUtils.Cluster.toplogy_supervisor/1`

## CFXRpc — Cross-Node RPC

Wraps `:erpc.call/5` and `:erpc.cast/4` with metrics, error handling, and routing:

```elixir
CFXRpc.call_on_random_node("options_feed", Module, :function, [args])
CFXRpc.route_to_node("options_feed", partition_key, Module, :function, [args])
CFXRpc.call(node, Module, :function, [args], timeout: 10_000)
CFXRpc.cast(node, Module, :function, [args])
```

**Key functions:**
- `call_on_random_node/4,5` — Finds nodes matching name filter, picks random. Retries after 5s if none found.
- `route_to_node/5,6` — Consistent-hash routing (partition term → specific node).
- `call/4,5` — Direct `:erpc.call` with default 10s timeout.
- `cast/4` — Fire-and-forget.

**Error handling:**
- `:badarg` → `ErrorMessage.bad_request/2`
- `:noconnection` → `ErrorMessage.service_unavailable/2`
- `:timeout` → `ErrorMessage.request_timeout/2`

**Metrics:** All calls go through `CFXMetrics.RpcMetrics.span_call/4` / `span_cast/4`.

## CFXRpc.Config

```elixir
CFXRpc.Config.call_directly?()   # true in dev/test, false in prod
CFXRpc.Config.distributed?()     # inverse
```

Pattern for conditional distributed features:
```elixir
if CFXRpc.Config.call_directly?() or SharedUtils.Cluster.node_equal?(node_type) do
  # Run locally
else
  # Route via RPC
end
```

## PubSub Topology

Three separate PubSub instances in `cfx_pub_sub`:

| PubSub Name | Pool Size | Used By |
|-------------|-----------|---------|
| `CFXWeb.PubSub` | pool: 4, registry: 6 | Web subscriptions, feature flag cache busting |
| `OptionsEventsProcessor.PubSub` | pool: 2 | Options trade events |
| `DarkPoolEventsProcessor.PubSub` | default | Dark pool/lit events |

**Topic conventions via `CFXPubSub`:**
- `"options_flow_events"` — Bulk options flow
- `"contract_activity"` / `"contract_activity:<symbol>"` — Per-symbol activity
- `"new_contract"` / `"new_contract:<symbol>"` — New contract alerts
- `"price_updates"` / `"price_updates:<symbol>"` — Price changes

Use `CFXPubSub.options_events_subscribe/1` and `CFXPubSub.options_events_broadcast/2` instead of `Phoenix.PubSub` directly.

## Node Naming

Production: `<release_name>@<ip>` (e.g., `options_feed@10.0.1.55`).
`SharedUtils.Cluster.filter_nodes/1` matches on node name string.

## Design Decisions

- **Separate PubSub instances** prevent event flooding across subsystems
- **ETS for feed state** avoids GenServer call bottlenecks
- **Consistent hashing** for feed routing enables per-query GenServer state reuse
- **Retry with sleep** in RPC handles transient cluster changes during deploys
