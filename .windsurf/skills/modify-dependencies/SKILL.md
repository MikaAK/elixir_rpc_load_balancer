---
name: modify-dependencies
description: "Umbrella dependency management patterns for the CheddarFlow project. TRIGGER when: adding dependencies, creating new apps, modifying mix.exs files, working with CFX.MixHelpers, or changing the mix_helpers.exs file. Also trigger when adding tags like :root, :web, :http to app configurations. DO NOT TRIGGER when: working with code that doesn't involve dependency or project configuration."
---

# Umbrella Dependency Management

Dependencies are centralized via `CFX.MixHelpers` in `mix_helpers.exs` at the project root.

## How It Works

1. **`umbrella_deps/0`** defines all shared external dependencies with versions and optional tags
2. **`sibling_deps/0`** auto-discovers all umbrella apps as `in_umbrella: true`
3. **Individual apps** call `CFX.MixHelpers.deps/1` with atom names and/or tags

## Tags

| Tag | Dependencies Included |
|-----|----------------------|
| `:root` | `libcluster`, `libcluster_ec2_tag_strategy` |
| `:web` | Phoenix web dependencies |
| `:http` | `finch`, `tesla`, `jason`, `error_message`, `castore`, `mint` |

## App mix.exs Pattern

```elixir
Code.require_file("mix_helpers.exs", "../..")

defmodule MyApp.MixProject do
  use Mix.Project
  @tags [:root, :http]
  @siblings [:schemas, :shared_utils]

  def project do
    CFX.MixHelpers.merge_umbrella_opts(
      app: :my_app,
      deps: deps()
    )
  end

  defp deps do
    CFX.MixHelpers.deps(
      @tags ++ @siblings ++ [
        :oban,
        {:some_dep, "~> 1.0"}
      ]
    )
  end
end
```

## `merge_umbrella_opts/1`

Merges standard umbrella options:
- Elixir version constraint (`~> 1.16`)
- Build/config/deps/lockfile paths to umbrella root
- `elixirc_paths` (includes `test/support` in dev/test)
- ExCoveralls test coverage
- Dialyzer configuration

## Key Rules

- **Never add a dep directly to an app's mix.exs if it's already in `umbrella_deps/0`** — reference by name
- **Always add new shared deps to `umbrella_deps/0`** in `mix_helpers.exs`
- **Use tags** for category-wide deps (e.g., `:http` for all HTTP clients)
- **Sibling deps are auto-discovered** — just list the app name as atom
- Some older apps manage deps directly without `CFX.MixHelpers`
- `sobelow` is always included regardless of tags

## Adding a New Umbrella App

1. Create app under `apps/`
2. Add `Code.require_file("mix_helpers.exs", "../..")` at top of `mix.exs`
3. Use `CFX.MixHelpers.merge_umbrella_opts/1` for project config
4. Use `CFX.MixHelpers.deps/1` for dependency resolution
5. If release app, add to `releases/0` in root `mix.exs`
6. Add tags: `:root` if joining cluster, `:http` if making HTTP requests
