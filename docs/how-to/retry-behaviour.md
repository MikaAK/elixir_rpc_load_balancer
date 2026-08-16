# How to Control Retry Behaviour

Two code paths can find themselves with nobody to talk to: a load-balanced `call/5`/`cast/5` whose `:pg` group is empty, and `call_on_random_node/5`/`cast_on_random_node/5` when no connected node matches the filter. Both happen routinely during cluster boot and rolling restarts. Rather than fail instantly, `rpc_load_balancer` backs off and retries.

## What is retried

Only the **no-route** condition — "there is currently no node to send this to". Once a node is selected and the RPC is dispatched, the result comes straight back: timeouts, `:noconnection`, remote raises, and application errors are **never** retried. Retrying those would risk running side-effecting work twice.

| Path | Retried condition | Final error |
|---|---|---|
| `call/5` / `cast/5` with `load_balancer:` | `get_members/1` returns no members | `%ErrorMessage{code: :service_unavailable, message: "no members registered"}` |
| `call_on_random_node/5` / `cast_on_random_node/5` | no node in `Node.list/0` matches the filter | `%ErrorMessage{code: :service_unavailable, message: "no nodes in cluster found with that filter"}` |

## Defaults

```elixir
config :rpc_load_balancer,
  retry?: true,
  retry_count: 5
```

With the default `retry_sleep` of 5 000 ms that is up to 6 attempts spread over 25 seconds before giving up. Retry is synchronous — the calling process sleeps between attempts.

## Per-call overrides

Every retry knob can be set on the call itself and takes precedence over the config:

```elixir
RpcLoadBalancer.call(node(), Mod, :fun, [arg],
  load_balancer: :my_lb,
  retry?: true,
  retry_count: 20,
  retry_sleep: 500
)

RpcLoadBalancer.call_on_random_node("worker", Mod, :fun, [arg],
  retry_count: :infinity,
  retry_sleep: 1_000
)
```

| Option | Default | Meaning |
|---|---|---|
| `:retry?` | config (`true`) | Set `false` to fail on the first empty result |
| `:retry_count` | config (`5`) | Number of retries after the first attempt. `:infinity` retries until a node appears |
| `:retry_sleep` | `5_000` | Milliseconds to sleep between attempts |

## Fail fast

For request paths where waiting 25 seconds is worse than a quick error, disable retry per call:

```elixir
case RpcLoadBalancer.call(node(), Mod, :fun, [arg], load_balancer: :my_lb, retry?: false) do
  {:ok, result} -> result
  {:error, %ErrorMessage{code: :service_unavailable}} -> fallback()
end
```

## Wait indefinitely

Boot-time wiring — e.g. a worker that must reach a coordinator before it can do anything — can wait forever with a short sleep:

```elixir
RpcLoadBalancer.call(node(), Coordinator, :register, [node()],
  load_balancer: :coordinator_lb,
  retry_count: :infinity,
  retry_sleep: 250
)
```

Combine with a `Task` and a timeout at the call site if you need an upper bound that isn't expressed in attempts.

## Named modules

Options pass straight through the generated functions:

```elixir
MyApp.LoadBalancer.call(node(), Mod, :fun, [arg], retry_count: :infinity, retry_sleep: 100)
```

## Interaction with `call_directly?`

When `call_directly?: true` (config or per call), or when the balancer runs `CallDirect`, the function runs locally via `apply/3` and no retry loop is entered.

## Using `RpcLoadBalancer.Retry` yourself

The same helper is public. Return `:retry` from the function to trigger another attempt; any other value is returned as-is, and exhausted retries return `:error`:

```elixir
RpcLoadBalancer.Retry.with_retry([retry_count: 3, retry_sleep: 100], fn ->
  case find_leader() do
    nil -> :retry
    leader -> {:ok, leader}
  end
end)
```
