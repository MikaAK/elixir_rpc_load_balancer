---
trigger: always_on
---

# Error Handling Patterns

## ErrorMessage Library
Use the `ErrorMessage` library (from `error_message` hex package) for all structured errors. Do **not** alias it as `MyApp.ErrorMessage` — use it directly.

## Return Types
Context functions must return:
- `{:ok, result}` for success
- `{:error, ErrorMessage.t()}` for errors
- `:ok` for void success operations

## Common Error Constructors
```elixir
ErrorMessage.not_found("resource not found", %{id: id})
ErrorMessage.bad_request("invalid input", %{field: "email"})
ErrorMessage.unauthorized("not authenticated")
ErrorMessage.forbidden("not allowed")
ErrorMessage.service_unavailable("service down", %{service: name})
ErrorMessage.bad_gateway("provider error", %{status: 502})
ErrorMessage.request_timeout("operation timed out")
ErrorMessage.internal_server_error("unexpected error", %{error: reason})
```

## Error Chaining with `with`
```elixir
def process(params) do
  with {:ok, validated} <- validate(params),
       {:ok, result} <- execute(validated) do
    {:ok, result}
  end
end
```

The `with` block automatically propagates `{:error, _}` tuples — do not add redundant `else` clauses unless transforming errors.

## Flatten Nested Case Statements
When `case` statements are nested 2+ levels deep and error branches share the same handling, flatten them into `with`. Do **not** use `with` when different error branches need distinct handling or when there is only one `case` level.

## Bug Fixing
- Always fix the root cause, not symptoms
- Never apply downstream patches for upstream issues
- Never mix atom and string keys to work around data shape issues
