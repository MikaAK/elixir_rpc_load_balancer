---
trigger: model_decision
description: Use this rule when you need to work on a GenServer or similar OTP behavior
---

# GenServer Patterns

## Initialization
**Always** use `handle_continue/2` for initialization work instead of blocking in `init/1`:

```elixir
def init(opts) do
  {:ok, %{opts: opts}, {:continue, :initialize}}
end

def handle_continue(:initialize, state) do
  {:noreply, do_initialization(state)}
end
```

## Option Validation
Use `NimbleOptions` for validating GenServer options:
```elixir
@definition [
  name: [type: :atom, required: true],
  interval: [type: :pos_integer, default: 5000]
]

def start_link(opts) do
  opts = NimbleOptions.validate!(opts, @definition)
  GenServer.start_link(__MODULE__, opts, name: opts[:name])
end
```

## ETS for Read-Heavy State
For state that is read frequently by many processes:
```elixir
:ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
```

## Supervision
Add GenServers to the application supervision tree in `application.ex`:
```elixir
children = [
  {MyGenServer, name: MyGenServer}
]
```
