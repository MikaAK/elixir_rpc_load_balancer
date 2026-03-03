# How to Filter Which Nodes Join a Load Balancer

By default, every node running the load balancer joins the `:pg` group. Use the `:node_match_list` option to restrict which nodes are eligible.

## Match by exact string

Pass a list of node name strings. Only nodes whose name matches one of the strings will join:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :filtered_balancer,
    node_match_list: ["worker1@host", "worker2@host"]
  )
```

Nodes not in the list still start the GenServer but do not register with the `:pg` group, so they won't appear in `get_members/1`.

## Match by regex

Use `Regex` patterns for flexible matching:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :worker_balancer,
    node_match_list: [~r/^worker/]
  )
```

This matches any node whose name starts with `worker`, such as `:"worker1@host"` or `:"worker_us_east@10.0.1.5"`.

## Combine strings and regexes

The match list accepts both types. A node joins if it matches any entry:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :mixed_balancer,
    node_match_list: ["primary@host", ~r/^replica/]
  )
```

## Allow all nodes (default)

Passing `:all` (or omitting the option) allows every node to join:

```elixir
{:ok, _pid} =
  RpcLoadBalancer.LoadBalancer.start_link(
    name: :open_balancer,
    node_match_list: :all
  )
```

## How matching works

The node's name is converted to a string with `to_string/1`, then tested against each entry using the `=~` operator. This means string entries perform a substring match and regex entries perform a regex match.
