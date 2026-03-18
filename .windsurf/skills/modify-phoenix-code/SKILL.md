---
name: modify-phoenix-code
description: "Phoenix framework patterns for the CheddarFlow project. TRIGGER when: writing or modifying Phoenix controllers, LiveView modules, templates, routes, plugs, components, layouts, or any code in the cfx_web app that touches the web layer. Also trigger when working with core_components.ex, router.ex, or endpoint.ex. DO NOT TRIGGER when: working with non-web Elixir code that doesn't involve Phoenix."
---

# Phoenix Code Guidelines

## Phoenix v1.8 Patterns

- **Always** begin LiveView templates with `<Layouts.app flash={@flash} ...>` wrapping all inner content
- `MyAppWeb.Layouts` is aliased in the `my_app_web.ex` file — no need to alias again
- Errors about missing `current_scope` assign mean you failed to follow Authenticated Routes guidelines or didn't pass `current_scope` to `<Layouts.app>` — fix by moving routes to the proper `live_session`
- `<.flash_group>` belongs **only** in the `layouts.ex` module — never call it elsewhere
- Use the `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for icons — never use `Heroicons` modules
- Use the imported `<.input>` component from `core_components.ex` for form inputs
- Overriding `<.input class="...">` replaces all default classes — your custom classes must fully style the input
- `Phoenix.View` is not included — don't use it
- Phoenix hooks used in LiveView DOM elements need an `id` on the element

## Router Patterns

- Router `scope` blocks include an optional alias prefixed for all routes within — be mindful to avoid duplicate module prefixes
- You **never** need to create your own alias for route definitions — the scope provides it:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser
        live "/users", UserLive, :index
      end

  This points to `AppWeb.Admin.UserLive`

## Project Router Structure

```
/api        — Absinthe.Plug (GraphQL endpoint, graphql pipeline with SessionContextPlug)
/api/graphiql — Absinthe.Plug.GraphiQL (playground, admin-only in dev/staging)
```

## Router Pipelines

```elixir
pipeline :auth_session do
  plug :fetch_session
  plug Auth0Session
end

pipeline :graphql do
  plug :accepts, ~w(json)
  plug SessionContextPlug
end

pipeline :admin do
  plug Auth0Session
  plug SessionContextPlug
  plug AdminRole
end
```
