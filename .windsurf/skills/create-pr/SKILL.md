---
name: create-pr
description: Creates a GitHub pull request — branches, commits, pushes, and opens a PR with gh cli.
---

# Create Pull Request

Creates a feature branch, commits staged changes, pushes, and opens a GitHub PR using `gh pr create --fill`.

## Inputs

- **Branch name** — descriptive feature branch name
- **Commit message** — follow conventional commit format: `<type>(<scope>): <description>`

## Steps

1. Confirm the branch name and commit message with the user.

2. Create and checkout the branch:
// turbo
```
git checkout -b <branch>
```

3. Stage all changes:
// turbo
```
git add -A
```

4. Commit with the conventional message:
```
git commit -m "<type>(<scope>): <description>"
```

5. Push the branch:
```
git push -u origin <branch>
```

6. Create the PR:
```
gh pr create --fill
```

7. Report the PR URL to the user.

## Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`

Example:
```
feat(auth): implement OAuth2 authentication

Add OAuth2 authentication support using Phoenix.Token
with support for multiple providers.
```
