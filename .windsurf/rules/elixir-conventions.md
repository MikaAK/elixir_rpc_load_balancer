---
trigger: always_on
---

# Elixir Code Conventions

## Strict Equality
- Use `===` instead of `==`
- Use `!==` instead of `!=`

## Nil Checks
- Use `is_nil(value)` instead of `value === nil`
- Use `not is_nil(value)` instead of `value !== nil`

## Empty Collections
- Use `Enum.empty?(list)` instead of `length(list) === 0` or `list === []`

## Integer Parsing
- **Never** use `String.to_integer/1` — it raises on invalid input
- Use a safe parsing function that returns `{:ok, integer} | {:error, term()}` instead

## Pipe Operator
- Only use `|>` when there are at least 2 operations in the chain
- Always start pipe chains with a raw value: `a |> b() |> c()` not `b(a) |> c()`

## Function Naming
- Predicate functions use `?` suffix: `valid?/1`, `active?/1`
- Reserve `is_` prefix for guard clauses only
- Do not use 1-2 letter acronym variable names

## Assertions in Tests
- Use `refute` instead of `assert !` or `assert not`
- Use `is_nil/1` guard in assertions

## Atoms vs Strings
- Never mix atoms and strings for the same key access
- If data comes as strings, keep it as strings; fix upstream if needed

## Module Aliases
- Do not alias modules that would conflict with library modules (e.g., don't alias `MyApp.Cache` if `elixir_cache` provides `Cache`)
- Do not alias modules that are already short

## Comments
- Do not write comments unless the code is genuinely unusual
- Do not add explanatory comments for straightforward operations
