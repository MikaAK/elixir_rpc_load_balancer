---
description: Run mix credo, mix dialyzer, and mix test from the project root and fix any issues found
---

# Run Checks and Fix Issues

Run the three main code quality checks in parallel, then fix any issues they report.

## Steps

1. Run all three commands **in parallel** (use non-blocking commands):
   - `mix credo --strict`
   - `mix dialyzer`
   - `mix test`
// turbo

2. Wait for all three commands to finish and collect their output.

3. If credo reported issues, fix each one following the project's Elixir conventions:
   - Do not add unnecessary comments
   - Use `===` over `==`, `!==` over `!=`
   - Use `is_nil/1` instead of `== nil`
   - Predicate functions end with `?`, reserve `is_` prefix for guards only
   - Start pipe chains with a raw value
   - Follow all rules in `.windsurf/rules/elixir-conventions.md`

4. If dialyzer reported warnings, fix each one:
   - Add or correct typespecs
   - Fix pattern match issues
   - Resolve unreachable code or invalid return types

5. If tests failed, fix each failure:
   - Read the failing test file and the corresponding source file
   - Determine whether the test or the source code is incorrect before choosing what to fix
   - Ask the user if unsure whether to fix the test or the implementation

6. After all fixes are applied, re-run all three checks in parallel to confirm everything passes.
// turbo

7. If any check still fails, repeat steps 3-6 until all three pass.

8. Once all three checks pass cleanly, report the final status to the user.
