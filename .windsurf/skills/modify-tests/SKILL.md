---
name: modify-tests
description: "Testing patterns for the CheddarFlow project. TRIGGER when: writing or modifying tests, test support modules, test configuration, FactoryEx factories, or test helper functions. Also trigger when setting up HTTP sandboxing, database sandbox, or Oban test helpers. DO NOT TRIGGER when: writing production code that doesn't involve test infrastructure."
---

# Testing Patterns

## General Rules

- **Always run tests from the app directory**: `cd apps/my_app && mix test`
- Use `FactoryEx` for all test data — never raw `Repo.insert!`
- Use `ErrorMessage` structs for error assertions
- Use `refute` instead of `assert !condition`
- Use `is_nil/1` guard instead of `== nil`
- Use `===` and `!==` for strict comparisons
- **Never use `Application.put_env` in tests** — use compile-time config or test-specific function definitions
- When fixing failing tests, first determine whether the code or the test is wrong before choosing what to fix
- Run tests after writing them

## HTTP Sandbox Pattern

API wrapper tests use `SharedUtils.Support.HTTPSandbox` and `SharedUtils.Support.TeslaMock`:

```elixir
defmodule MyApi.SomeTest do
  use SharedUtils.BaseCase, async: true

  alias SharedUtils.Support.TeslaMock

  test "fetches data" do
    TeslaMock.mock([
      {:get, "https://api.example.com/data",
       fn %Tesla.Env{} ->
         %Tesla.Env{status: 200, body: %{"result" => "ok"}}
       end}
    ])

    assert {:ok, _} = MyApi.get_data()
  end
end
```

Disable sandboxing for integration tests: `setup :disable_http_sandbox!`

Override adapter: `SharedUtils.Support.HTTPSandbox.register_overrides!(adapter: Tesla.Adapter.Httpc)`

## Database Sandbox

- `Schemas.Repo` and `Schemas.JobsRepo` both support `Ecto.Adapters.SQL.Sandbox`
- `SharedUtils.Support.DataCase` or equivalent base case modules handle setup

## Compile-Time Environment Branching

Use `Mix.env()` at compile time (not available at runtime in releases):

```elixir
if Mix.env() === :test do
  @default_servers []
else
  @default_servers [%{filter_by: %{side: %{in: [:ask, :above]}}, permanent?: true}]
end
```

Used for: disabling permanent feed servers in test, adding simulator producers in dev, disabling Oban cleanup, configuring PubSub test topics.

## Test Support Modules

- `SharedUtils.BaseCase` — Base test case with HTTP sandbox
- `SharedUtils.Support.TeslaMock` — Tesla mock helper
- `SharedUtils.Support.HTTPSandbox` — HTTP sandboxing via `SandboxRegistry`
- `CFXPubSub.Support.Setup` — PubSub test topic configuration
- `FactoryEx` factories in `test/support/` of each app

## Testing Oban Workers

```elixir
use Oban.Testing, repo: Schemas.JobsRepo

test "enqueues job" do
  assert {:ok, _} = MyWorker.new(%{key: "value"}) |> Oban.insert()
  assert_enqueued(worker: MyWorker)
end
```

## Testing GenServers and Supervisors

- Start GenServers with `start_supervised!/1`
- Feed server test support in `shared_feed_utils/test/support/`
- PubSub tests: subscribe, trigger event, `assert_receive`

## Property-Based Testing

`propcheck` available in `:test` env, primarily in `schemas` and `shared_utils` apps.
