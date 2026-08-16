# How to Test with the CallDirect Strategy

When testing code that uses `RpcLoadBalancer`, you typically don't have a multi-node cluster available. The `CallDirect` selection algorithm solves this by executing calls locally via `apply/3` instead of going through `:erpc`.

## Configure your load balancer for tests

Pass `SelectionAlgorithm.CallDirect` as the selection algorithm when starting a load balancer in your test setup:

```elixir
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, _pid} =
  RpcLoadBalancer.start_link(
    name: :my_balancer,
    selection_algorithm: SelectionAlgorithm.CallDirect
  )
```

With `CallDirect` active:

- `call/5` with `load_balancer: :name` executes `apply(module, fun, args)` and returns `{:ok, result}`
- `cast/5` with `load_balancer: :name` executes `spawn(module, fun, args)` and returns `:ok`
- No `:erpc` calls are made and no cluster nodes are required
- Node selection is skipped entirely (no `:pg` lookup, no `[:rpc_load_balancer, :node_selected]` event); the `[:rpc_load_balancer, :rpc, ...]` span still fires

## Use it in ExUnit setup

A typical test module that depends on a load balancer. `start_link/1` returns only after the balancer has joined its `:pg` group, so no sleep is needed:

```elixir
defmodule MyApp.WorkerTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  setup do
    lb_name = :"test_lb_#{System.unique_integer([:positive])}"

    start_supervised!(
      {RpcLoadBalancer, name: lb_name, selection_algorithm: SelectionAlgorithm.CallDirect}
    )

    %{lb_name: lb_name}
  end

  test "call executes the function", %{lb_name: lb_name} do
    assert {:ok, 42} ===
             RpcLoadBalancer.call(node(), Kernel, :+, [40, 2], load_balancer: lb_name)
  end

  test "cast fires asynchronously", %{lb_name: lb_name} do
    test_pid = self()

    assert :ok ===
             RpcLoadBalancer.cast(
               node(),
               Kernel,
               :apply,
               [fn -> send(test_pid, :done) end, []],
               load_balancer: lb_name
             )

    assert_receive :done, 1000
  end
end
```

## Named modules in tests

A module defined with `use RpcLoadBalancer` is registered under its own name, so only one instance can run per node. Start it with `start_supervised!/1` and it is torn down between tests:

```elixir
defmodule MyApp.LoadBalancerTest do
  use ExUnit.Case, async: true

  setup do
    start_supervised!(MyApp.LoadBalancer)
    :ok
  end

  test "routes through the module" do
    assert {:ok, :called} === MyApp.LoadBalancer.call(node(), Kernel, :apply, [fn -> :called end, []])
  end
end
```

If the module is already started by your application (it usually is), skip the `setup` and call it directly.

## Application-level configuration

If your application starts a load balancer in its supervision tree, switch the algorithm based on the compile-time environment:

```elixir
defmodule MyApp.LoadBalancer do
  @algorithm if Mix.env() === :test,
               do: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirect,
               else: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin

  use RpcLoadBalancer, selection_algorithm: @algorithm
end
```

Or with the tuple form:

```elixir
defmodule MyApp.Application do
  use Application

  @selection_algorithm if Mix.env() === :test,
                         do: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirect,
                         else: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin

  @impl true
  def start(_type, _args) do
    children = [
      {RpcLoadBalancer,
       name: :my_balancer,
       selection_algorithm: @selection_algorithm}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

This uses a module attribute evaluated at compile time, which avoids calling `Mix.env()` at runtime (where it doesn't exist in releases).

## Alternative: the `call_directly?` config flag

If you would rather keep the production algorithm in place and short-circuit at the call site, set the application flag in `config/test.exs`:

```elixir
config :rpc_load_balancer, call_directly?: true
```

With `call_directly?: true`, `call/5`, `cast/5`, `call_on_random_node/5`, and `cast_on_random_node/5` all execute locally regardless of which algorithm the balancer runs. It can also be passed per call (`call_directly?: true`) to override the config for a single invocation.

The difference from `CallDirect`: the flag is global (every balancer in the VM), while `CallDirect` is per balancer. Prefer `CallDirect` when you want one balancer local and another exercising real selection.

## Why CallDirect should be used in tests

- **No cluster required** — tests run on a single node, so `:erpc` calls to remote nodes would fail with `{:error, %ErrorMessage{code: :service_unavailable}}`
- **Deterministic** — `apply/3` runs synchronously in the calling process, making assertions straightforward
- **Fast** — skips `:erpc` serialization and the `:pg` member lookup entirely (~0.04 μs per call)
- **Isolated** — each test can start its own load balancer with a unique name without interfering with other tests
