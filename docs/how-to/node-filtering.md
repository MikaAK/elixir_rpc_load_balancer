# How to Filter Which Nodes Join a Load Balancer

By default, every node running a load balancer joins its `:pg` group and becomes a routing target. Use the `:node_match_list` option to restrict which nodes are eligible, and `excluded_node_patterns` to carve out classes of nodes (QA, canary, ...) from routing filters cluster-wide.

## Match by string

Pass a list of strings. A node joins if its name **contains** one of them (substring match, not equality):

```elixir
{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :filtered_balancer,
    node_match_list: ["worker1@host", "worker2@host"]
  )
```

Nodes not in the list still start the balancer supervisor (so they can select and call), but do not register with the `:pg` group and won't appear in `get_members/1`.

## Match by regex

Use `Regex` patterns for flexible matching:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :worker_balancer,
    node_match_list: [~r/^worker/]
  )
```

This matches any node whose name starts with `worker`, such as `:"worker1@host"` or `:"worker_us_east@10.0.1.5"`.

## Combine strings and regexes

The match list accepts both types. A node joins if it matches any entry:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :mixed_balancer,
    node_match_list: ["primary@host", ~r/^replica/]
  )
```

## Allow all nodes (default)

Passing `:all` (or omitting the option) allows every node to join:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :open_balancer,
    node_match_list: :all
  )
```

## Selectors vs. targets

`node_match_list` only decides whether **this** node registers as a target. A web node that never matches can still start the same balancer and route calls to the worker nodes that do:

```elixir
# On every node, web and worker alike:
defmodule MyApp.WorkerBalancer do
  use RpcLoadBalancer, node_match_list: ["worker"]
end

# Web nodes never join, but can still call:
MyApp.WorkerBalancer.call(node(), Jobs, :run, [job])
```

## Exclude classes of nodes with `excluded_node_patterns`

Substring filters have a footgun: a `"worker"` filter also matches `worker_qa@host`. Configure `excluded_node_patterns` to keep such nodes out of any filter that doesn't name them explicitly:

```elixir
# config/config.exs
config :rpc_load_balancer, excluded_node_patterns: ["_qa", "_canary"]
```

With that in place:

| Node | Filter `"worker"` | Filter `"worker_qa"` |
|---|---|---|
| `worker@host` | matches | no |
| `worker_qa@host` | **excluded** | matches |
| `worker_canary@host` | **excluded** | no |

The rule: a node whose short name (before `@`) contains an excluded pattern is dropped from a filter **unless the filter itself contains that pattern**. Regex filters are checked against their source string. The default is `[]` (no exclusions).

This applies everywhere node names are matched — `node_match_list` entries and the `node_filter` argument of `call_on_random_node/5` / `cast_on_random_node/5` — because both route through `RpcLoadBalancer.NodeFilter.matches?/2`.

## How matching works

`RpcLoadBalancer.NodeFilter.matches?(node, filter)`:

1. Converts the node name to a string with `to_string/1`
2. Tests it against the filter with `=~` — substring for strings, regex match for `Regex`
3. If it matched, checks `excluded_node_patterns`: for each pattern present in the node's short name but absent from the filter, the match is rejected

You can call it directly to test a filter, optionally passing an explicit exclusion list:

```elixir
RpcLoadBalancer.NodeFilter.matches?(:"worker_qa@host", "worker", ["_qa"])
# => false
```
