# How to Test with the CallDirect Strategy

When testing code that uses `RpcLoadBalancer.LoadBalancer`, you typically don't have a multi-node cluster available. The `CallDirect` selection algorithm solves this by executing calls locally via `apply/3` instead of going through `:erpc`.

## Configure your load balancer for tests

Pass `SelectionAlgorithm.CallDirect` as the selection algorithm when starting a load balancer in your test setup:

```elixir
alias RpcLoadBalancer.LoadBalancer
alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

{:ok, _pid} =
  LoadBalancer.start_link(
    name: :my_balancer,
    selection_algorithm: SelectionAlgorithm.CallDirect
  )
```

With `CallDirect` active:

- `LoadBalancer.call/5` executes `apply(module, fun, args)` and returns `{:ok, result}`
- `LoadBalancer.cast/5` executes `spawn(module, fun, args)` and returns `:ok`
- No `:erpc` calls are made
- No cluster nodes are required

## Use it in ExUnit setup

A typical test module that depends on a load balancer:

```elixir
defmodule MyApp.WorkerTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  setup do
    lb_name = :"test_lb_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      LoadBalancer.start_link(
        name: lb_name,
        selection_algorithm: SelectionAlgorithm.CallDirect
      )

    # Allow the GenServer to finish registration
    Process.sleep(50)

    %{lb_name: lb_name}
  end

  test "call executes the function", %{lb_name: lb_name} do
    assert {:ok, 42} === LoadBalancer.call(lb_name, Kernel, :+, [40, 2])
  end

  test "cast fires asynchronously", %{lb_name: lb_name} do
    test_pid = self()

    assert :ok ===
             LoadBalancer.cast(lb_name, Kernel, :apply, [
               fn -> send(test_pid, :done) end,
               []
             ])

    assert_receive :done, 1000
  end
end
```

## Application-level configuration

If your application starts a load balancer in its supervision tree, you can switch the algorithm based on the compile-time environment:

```elixir
defmodule MyApp.Application do
  use Application

  @selection_algorithm if Mix.env() === :test,
                         do: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirect,
                         else: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin

  @impl true
  def start(_type, _args) do
    children = [
      {RpcLoadBalancer.LoadBalancer,
       name: :my_balancer,
       selection_algorithm: @selection_algorithm}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

This uses a module attribute evaluated at compile time, which avoids calling `Mix.env()` at runtime (where it doesn't exist in releases).

## Why CallDirect should always be used in tests

- **No cluster required** — tests run on a single node, so `:erpc` calls to remote nodes will fail with `{:error, %ErrorMessage{code: :service_unavailable}}`
- **Deterministic** — `apply/3` runs synchronously in the calling process, making assertions straightforward
- **Fast** — skips `:erpc` serialization and the `:pg` member lookup entirely
- **Isolated** — each test can start its own load balancer with a unique name without interfering with other tests
