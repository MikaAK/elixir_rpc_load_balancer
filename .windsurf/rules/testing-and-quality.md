---
trigger: model_decision
description: Use this rule when you need to work on code that requires testing and quality checks
---

# Testing and Code Quality Enforcement

After completing each logical section of code changes, you MUST:

## 1. Write Tests
- Write comprehensive tests for all new functionality before moving to the next section
- Tests should cover happy paths, edge cases, and error conditions

## 2. Run Tests
After writing tests, execute them:
```bash
mix test
```

If tests fail, fix the issues before proceeding.

## 3. Run Credo
Check code style and consistency:
```bash
mix credo --strict
```

Address any warnings or errors before proceeding.

## 4. Run Dialyzer
Perform static analysis:
```bash
mix dialyzer
```

Fix any type errors or warnings before proceeding.

## Workflow Summary
For each section of work:
1. Implement the feature/fix
2. Write tests
3. Run `mix test`
4. Run `mix credo --strict`
5. Run `mix dialyzer`
6. Only proceed to the next section when all checks pass
