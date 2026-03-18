---
name: modify-api-wrapper
description: "API wrapper patterns for the CheddarFlow project. TRIGGER when: writing or modifying API wrapper apps (apps with _api suffix), making HTTP requests to external services, working with SharedUtils.HTTP, Tesla middleware, or Finch pools. Also trigger when creating response structs with new!/1 constructors. DO NOT TRIGGER when: working with internal Elixir code that doesn't make external HTTP calls."
---

# API Wrapper Pattern

All external API integrations follow the `SharedUtils.HTTP` pattern built on Tesla + Finch.

## Structure

```
apps/my_api/
├── lib/
│   ├── my_api.ex              # Public interface — domain functions
│   ├── my_api/
│   │   ├── http.ex            # HTTP client module (implements SharedUtils.HTTP behaviour)
│   │   ├── middleware/         # Custom Tesla middleware (error handling, auth)
│   │   └── responses/         # Response structs with new!/1 constructors
├── test/
└── mix.exs
```

## HTTP Client Module Pattern

```elixir
defmodule MyApi.HTTP do
  @behaviour SharedUtils.HTTP

  @adapter {Tesla.Adapter.Finch, name: __MODULE__}
  @api_base "https://api.example.com"

  @middleware [
    {Tesla.Middleware.BaseUrl, @api_base},
    {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> @token}]},
    Tesla.Middleware.PathParams,
    MyApi.Middleware.ErrorHandler,
    Tesla.Middleware.Logger,
    Tesla.Middleware.JSON,
    Tesla.Middleware.Retry
  ]

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts
    |> Keyword.put_new(:name, __MODULE__)
    |> Keyword.put(:pools, %{@api_base => [protocol: :http1, size: 10]})
    |> SharedUtils.HTTP.child_spec()
  end

  @impl SharedUtils.HTTP
  def new(opts \\ []) do
    opts = Keyword.put_new(opts, :client, __MODULE__)
    SharedUtils.HTTP.client(@middleware, @adapter, opts)
  end

  def get(url, opts \\ []), do: SharedUtils.HTTP.get(new(), url, opts)
  def post(url, body, opts \\ []), do: SharedUtils.HTTP.post(new(), url, body, opts)
end
```

## Key Conventions

- **Finch pools**: Each API gets its own named Finch pool in its supervision tree
- **Tesla.Middleware.PathParams**: URL template interpolation (e.g., `/v3/options/:symbol`)
- **Error handling**: Use `SharedUtils.HTTP.Middleware.ErrorHandler` or custom middleware mapping HTTP status codes to `ErrorMessage` structs
- **Response structs**: Typed structs with `new!/1` constructors parsing API response maps
- **Sandboxing**: In test, `SharedUtils.HTTP` auto-swaps to `Tesla.Mock` adapter via `SharedUtils.Support.HTTPSandbox`
- **Return types**: Functions return `SharedUtils.HTTP.http_response(data)` which is `{:ok, data} | {:error, ErrorMessage.t()}`

## Existing API Wrappers

| Module | Base URL | Auth Method |
|--------|----------|-------------|
| `PolygonApi.HTTP` | `https://api.polygon.io` | Query param `apiKey` |
| `TiingoApi.HTTP` | `https://api.tiingo.com` | Header `Authorization: Token <key>` |
| `StripeApi.HTTP` | `https://api.stripe.com` | Header `Authorization: Bearer <key>` |
| `TradeAlertApi.HTTP` | TradeAlert endpoint | Header-based API key |
| `DxFeedApi.HTTP` | DxFeed endpoint | Basic auth |
| `Auth0Api.HTTP` | Auth0 domain | Bearer token (OAuth2 M2M) |
| `DiscordApi.HTTP` | `https://discord.com/api` | Bot token header |
| `MetaApi.HTTP` | `https://graph.facebook.com` | Query param `access_token` |
| `FmpApi.HTTP` | `https://financialmodelingprep.com/api` | Query param `apikey` |

## Testing

- Use `SharedUtils.Support.TeslaMock.mock/1` for mock responses
- Tests are async-safe via `SandboxRegistry`
- Disable sandboxing for integration tests: `SharedUtils.Support.HTTPSandbox.disable_http_sandbox!/1`

## Adding a New API Wrapper

1. Create app under `apps/my_api/`
2. Add `:http` tag or explicit deps (`finch`, `tesla`, `jason`, `error_message`) in `mix.exs`
3. Define `MyApi.HTTP` implementing `SharedUtils.HTTP` behaviour
4. Add `child_spec` for Finch pool startup
5. Start the HTTP pool in the consuming release app's supervision tree
6. Define response structs with `new!/1` in `MyApi.Responses.*`
7. Public API functions go in the root `MyApi` module
