---
name: modify-auth
description: "Authentication and authorization patterns for the CheddarFlow project. TRIGGER when: writing or modifying authentication, authorization, sessions, Auth0 integration, user access control, entitlements, or any plug/middleware that checks user identity or permissions. Also trigger when working with SessionCache, JWKS, or Ueberauth. DO NOT TRIGGER when: working with code that doesn't involve auth or user identity."
---

# Authentication & Authorization

## Auth0 Integration

The `auth` app provides Auth0 integration:

- **`Auth.Auth0`** — GenServer managing Auth0 Management API access tokens and profile fetching. Uses `NimbleOptions`.
- **`Auth.Auth0.JWKSStrategy`** — JWKS key caching via `joken_jwks` for JWT verification
- **`Auth.Sessions.SessionCache`** — Redis-backed session cache (via `elixir_cache`)
- **`Auth0Api`** — Low-level HTTP wrapper for Auth0 Management API

## Authentication Flow

1. User hits `/auth/:provider` → Ueberauth initiates Auth0 OAuth2 flow
2. Auth0 callback at `/auth/:provider/callback` → `AuthController.callback/2`
3. Session created with Auth0 user info stored in Redis via `SessionCache`
4. Subsequent requests use `Auth0Session` plug to load session from cookie → Redis

## Key Plugs (`CFXWeb.Plugs`)

- **`Auth0Session`** — Fetches/validates Auth0 session from cookie/Redis
- **`SessionContextPlug`** — Extracts current user, injects into conn assigns and Absinthe context
- **`AdminRole`** — Guards routes requiring admin role

## Absinthe Auth Middleware

`CFXWeb.Schema.Middleware.SessionAdminAuthorization` checks authorization before all queries/mutations/subscriptions.

## Session Storage

Redis via `Auth.Sessions.SessionCache`:
- Prod: `uri: <REDIS_URI>, pool_size: 10`
- Dev/test: `pool_size: 2`
- Keyed by Auth0 user ID

## Entitlements

`Schemas.Entitlements` controls feature access:
- Linked to Stripe subscriptions
- Determines premium feature access (dark pool, gamma exposure, etc.)
- Checked in GraphQL middleware and feed server authorization

## Configuration

- **Dev**: Staging Auth0 tenant (`cflow-staging.us.auth0.com`)
- **Prod**: Production tenant with separate `web_app` and `cfx_app` client credentials
- Secrets loaded from 1Password at deploy time

## Key Rules

- Never store Auth0 secrets in code or config — use environment variables
- Always use `SessionContextPlug` in pipelines needing user context
- Admin routes conditionally compiled via `CFXWeb.Config.admin_routes?()` (disabled in prod frontend)
- Use `Auth.Auth0.ResponseCache` for caching Management API responses to avoid rate limits
