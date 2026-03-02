---
description: Run mix test and fix any failing tests
---

# Run Tests and Fix Failures

Run `mix test` and fix any failing tests.

## Steps

1. Run the tests:
   - If the user provided a specific test file or line, use `mix test <path>` or `mix test <path>:<line>`
   - Otherwise run `mix test`
// turbo

2. Wait for the command to finish and collect its output.

3. If all tests pass, report success and stop.

4. If tests failed, for **each** failure:
   - Read the failing test file and the corresponding source file
   - Determine whether the **test** or the **source code** is incorrect before choosing what to fix
   - Ask the user if unsure whether to fix the test or the implementation
   - Apply the minimal fix needed

5. After all fixes are applied, re-run the same test command to confirm everything passes.
// turbo

6. If any tests still fail, repeat steps 4-5 until all tests pass.

7. Once all tests pass cleanly, report the final status to the user.
