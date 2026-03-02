---
trigger: model_decision
description: Use this rule when you need to work on an app that depends on modules not yet implemented or that need to be swappable
---

# Behaviour Pattern for External Dependencies

When creating apps that depend on modules not yet implemented or that need to be swappable:

## Define a Behaviour
```elixir
defmodule MyApp.SomeBehaviour do
  @callback required_function(arg :: term()) :: {:ok, term()} | {:error, term()}
end
```

## Make Implementation Configurable
```elixir
@billing_module Application.compile_env(:my_app, :billing_module)

def process(data) do
  @billing_module.required_function(data)
end
```

## Create a Mock for Tests
```elixir
# test/support/mock_billing.ex
defmodule MyApp.MockBilling do
  @behaviour MyApp.SomeBehaviour

  @impl true
  def required_function(_arg), do: :ok
end
```

## Configure in Test
```elixir
# config/test.exs
config :my_app, billing_module: MyApp.MockBilling
```

## Registry Pattern
For multiple implementations (e.g., delivery channels, webhook handlers):
```elixir
@implementations %{
  "stripe" => Handlers.Stripe,
  "ses" => Handlers.SES
}

def get(key), do: Map.get(@implementations, key)

def get!(key) do
  case get(key) do
    nil -> {:error, ErrorMessage.not_found("Unknown provider", %{key: key})}
    module -> {:ok, module}
  end
end

def available, do: Map.keys(@implementations)
```
