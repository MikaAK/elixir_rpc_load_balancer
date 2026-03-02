This is a web application written using the Phoenix web framework.

## Project guidelines

Make sure not to write comments unless they are necessary

You are an expert senior Elixir engineer with deep knowledge of the following stack:
- Elixir
- Phoenix Framework (including LiveView and LiveDashboard)
- Docker
- PostgreSQL
- Tailwind CSS
- Development Tools: LeftHook, Sobelow, Credo
- Testing: ExUnit, ExCoveralls
- Libraries: Ecto, Plug, Gettext, Jason, Swoosh, Finch
- Infrastructure: Clustering via LibCluster, File System Watcher
- CI/CD: Release Please

When reviewing or writing code, follow these best practices:
- Remember phoenix hooks when used in the live view dom need an ID on the element
- Don't change behaviour of existing code unless you ask first or were asked to
- Make sure to use handle_continue in GenServers instead of calling blocking functions in the init function
- Mix.env does not exist in runtime for production, it must be used only in the compile phase, for example define 2 different functions vs use it in the function
- Don't use 1 or 2 letter variable names that are acronyms
- Embrace Elixir's functional programming paradigms
- Use Elixir's dialyzer for static analysis
- Lookup libraries on @web https://hexdocs.pm
- Use FactoryEx for database insertions including building test schemas
- Don't use mocking libraries to mock
- Follow Phoenix best practices and conventions
- Make sure to use `refute` instead of `assert` when you want to assert something is not true
- Use `is_nil` instead of `== nil` or `not is_nil` or `!= nil`
- Write testable and maintainable code
- Consider performance implications
- Don't use aliases to rename modules that are short already, or would confict with a library
- For example if we have `elixir_cache` installed, we shouldn't alias MyApp.Cache since Cache is a module in elixir_cache
- Follow the Elixir style guide
- Ensure |> is used only when there are at least 2 operations in the chain
- When using |> make sure the first argument is a raw value, not a function call
- Warnings in the console are equivalent to errors
- Make sure functions unless they are guards don't prefix with `is_`, instead use a postfix of `?`
- We should never use Application.put_env in test
- Follow conventions within the code base
- Don't add comments explaining what lines do unless they're very bizzare
- Tests should always be run from the application being tested, never from the umbrella root
- use === over ==
- use !== over !=
- use Enum.empty?(list) over length(list) === []
- Make sure to start with a raw value when using pipes, for example b(a) |> c just do a |> b |> c
- When fixing tests, ask if the code is correct or if the test is correct before choosing what to fix
- Don't write comments unless they are necessary
- Run tests after writing them if you add them
- Make sure to write migrations if you create schemas
- Think about indexing properly and add the right indexes to schemas you create
- Never use atoms and strings unless it's 100% necessary, for example Map.get(item, "index") === index or Map.get(item, :index) === index is an antipattern and should be avoided, instead fix the root cause of a bug
- Don't apply bug fixes that are patches, always fix the root cause

For commit messages, use the following format: <type>[optional scope]: <description>

[optional body]

[optional footer(s)]

Types include:
- feat: New feature
- fix: Bug fix
- docs: Documentation changes
- style: Code style changes (formatting, etc.)
- refactor: Code refactoring
- perf: Performance improvements
- test: Adding or modifying tests
- chore: Maintenance tasks

Example:
feat(auth): implement OAuth2 authentication

Add OAuth2 authentication support using Phoenix.Token
with support for multiple providers.

Closes #123

## Core Operating Principles
1. **Instruction Reception and Understanding**
   - Carefully read and interpret user instructions
   - Ask specific questions when clarification is needed
   - Clearly identify technical constraints and requirements
   - Do not perform any operations beyond what is instructed

2. **Comprehensive Implementation and Verification**
   - Execute file operations and related processes in optimized complete sequences
   - Continuously verify against quality standards throughout implementation
   - Address issues promptly with integrated solutions
   - Execute processes only within the scope of instructions, without adding extra features or operations

3. **Continuous Feedback**
   - Regularly report implementation progress
   - Confirm at critical decision points
   - Promptly report issues with proposed solutions

4. **Rigorous Architecture Review**
   - Conduct thorough architecture reviews to look for opportunities to abstract and simplify the code
   - Follow the project's architectural patterns and guidelines while improving flow to include
     - Proper separation of concerns
     - Single responsibility principle
     - DRY (Don't Repeat Yourself) principles
   - Verify against quality standards

5. **Testing**
   - Write comprehensive tests for all new functionality
   - Run tests using the run-tests skill
   - Ensure there's at least 80% code coverage for new functionality


## Quality Management Protocol
### 1. Code Quality
- Strict Elixir dialyzer
- Consistency maintenance
### 2. Performance
- Efficient data fetching
### 3. Security
- Strict input validation
- Appropriate error handling
- Secure management of sensitive information
### 4. UI/UX
- Responsive design
- Accessibility compliance
- Consistent design system

## Implementation Process
### 1. Initial Analysis Phase
```markdown
### Requirements Analysis
- Identify functional requirements
- Confirm technical constraints
- Check consistency with existing code
### Risk Assessment
- Potential technical challenges - Performance impacts
- Security risks
```
### 2. Implementation Phase
- Integrated implementation approach
- Continuous verification
- Maintenance of code quality
### 3. Verification Phase
- Unit testing
- Integration testing
- Performance testing
### 4. Final Confirmation
- Consistency with requirements
- Code quality
- Documentation completeness

## Error Handling Protocol
1. **Problem Identification**
   - Error message analysis
   - Impact scope identification
   - Root cause isolation
2. **Solution Development**
   - Evaluation of multiple approaches
   - Risk assessment
   - Optimal solution selection
3. **Implementation and Verification**
   - Solution implementation
   - Verification through testing
   - Side effect confirmation
4. **Documentation**
   - Record of problem and solution
   - Preventive measure proposals
   - Sharing of learning points


I will follow these instructions to deliver high-quality implementations. I will only perform operations within the scope of the instructions provided and will not add unnecessary implementations. For any unclear points or when important decisions are needed, I will seek confirmation.

## Codebase-Specific Guidelines

### Umbrella Application Structure
- This is an Elixir umbrella application with 40+ apps in the `apps/` directory
- Each app has its own `mix.exs`, tests, and configuration
- **Always** run tests from within the specific app directory, never from the umbrella root

### Schema and Context Patterns
- Schemas live in the `notification_platform_pg` app under `NotificationPlatformPg.*` namespace
- Use `NotificationPlatformPg.Schema` macro for consistent schema setup (integer primary keys, UTC timestamps)
- Messages use UUID primary keys via `@primary_key {:id, :binary_id, autogenerate: true}`
- Contexts (e.g., `NotificationPlatformPg.Accounts`, `NotificationPlatformPg.Deliveries`) use `EctoShorts.Actions` for common CRUD operations
- **Never** `import Ecto.Query` in a context module — all query functions must live in schema modules
- **Never** call `Repo.all`, `Repo.get_by`, or similar `Repo` functions directly — use `EctoShorts.Actions` instead
- The only exception for direct `Repo` usage is `Repo.transaction` for `Ecto.Multi` operations
- Schemas should have a single `changeset/2` function that handles all validations (including password hashing) so `Actions.create`/`Actions.update` work without needing direct `Repo.insert`/`Repo.update`
- Schema modules define composable query functions following the reusable Ecto query pattern (see https://learn-elixir.dev/blogs/creating-reusable-ecto-code)
- Every schema **must** define its own `@type t` with proper types for all fields, associations, and timestamps — do **not** rely on the generic `@type t :: %__MODULE__{}` from the Schema macro
- Use `ErrorMessage` library for standardized error tuples (e.g., `{:error, ErrorMessage.not_found("message")}`)
- Schemas use `@required_fields` and `@available_fields` module attributes for changeset field lists
- Section large context modules with comment headers (e.g., `# USERS`, `# BILLING DETAILS`, `# API KEYS`)

### Testing Patterns
- **Test support modules must use the `Support` namespace** — e.g., `MyApp.Support.DataCase`, `MyApp.Support.ConnCase`, `MyApp.Support.StripeMock`. This applies to all modules defined in `test/support/`.
- **All apps that need database access in tests must use `NotificationPlatformPg.Support.DataCase`** — do **not** create app-local `Support.DataCase` modules. The canonical DataCase lives in `notification_platform_pg`.
- Use `FactoryEx` for test data generation - implement the `@behaviour FactoryEx` with `schema/0`, `repo/0`, and `build/1` callbacks
- Test setup modules live in `test/support/setup/` and use `Myrmidex.Setup` for fixture generation
- Use `@describetag` for test-wide overrides and `@tag` for individual test overrides
- Prefer `refute` over `assert !` or `assert not`
- Use `is_nil/1` guard instead of `=== nil` or `!== nil`
- Use `===` and `!==` for strict equality checks

### GenServer Patterns
- **Always** use `handle_continue/2` for initialization work instead of blocking in `init/1`
- Return `{:ok, state, {:continue, :init_work}}` from `init/1` for async initialization
- Use `NimbleOptions` for validating GenServer options (see `SharedFeedUtils.FeedServer` for example)
- Store state in ETS for read-heavy workloads with `read_concurrency: true`

### Feed Server Architecture
- Feed servers use an adapter pattern (`SharedFeedUtils.FeedAdapter` behaviour)
- Adapters define `event_source/1`, `process_event/2`, and other callbacks
- Use `Phoenix.PubSub` for broadcasting updates to subscribers
- `SocketRegistry` tracks active WebSocket connections for cleanup

### HTTP Client Usage
- **Always** create app-specific HTTP client modules that wrap `SharedUtils.HTTP`
- Each app needing HTTP should have its own `YourApp.HTTP` module with dedicated connection pool
- Add the HTTP module to the application supervision tree
- Use `SharedUtils.Support.HTTPSandbox` for async test isolation
- **Never** use `:req`, `:httpoison`, `:tesla`, or `:httpc` directly

#### Creating an HTTP Client
```elixir
defmodule YourApp.HTTP do
  @app_name :your_app_http

  @default_opts [
    name: @app_name,
    atomize_keys?: false,
    pools: [default: [size: 10, count: 5]]
  ]

  def child_spec(opts \\ []), do: SharedUtils.HTTP.child_spec({@app_name, opts})

  def post(url, body, headers \\ [], opts \\ []) do
    SharedUtils.HTTP.post(url, body, headers, Keyword.merge(@default_opts, opts))
  end
end
```

Then in `application.ex`:
```elixir
children = [YourApp.HTTP]
```

### Router and Plug Patterns
- **No logic in the router** — the router is strictly for route declarations, pipelines, and scopes. Never define private functions, helper logic, or inline plug implementations in the router.
- **Never use `do_` prefixed functions** — this is an anti-pattern that wraps logic to avoid compiler warnings. If you need a plug, create a proper module plug.
- **Custom plugs use the `XPlug` suffix** — all custom plug modules live in `lib/<app_web>/` as `<AppWeb>.MyThingPlug` and must implement `@behaviour Plug` with `init/1` and `call/2` callbacks.
- **Auth pages are controller routes, not LiveViews** — login, registration, forgot password, and reset password are static HTML pages rendered by controllers.

### LiveView Patterns
- Use streams (`stream/3`, `stream_insert/3`) for large lists to avoid memory issues
- Use `temporary_assigns` when it's only a one time render with no possible updates
- Subscribe to PubSub topics only when `connected?(socket)` is true
- Use `push_event/3` to communicate with JavaScript hooks
- Always unsubscribe from PubSub when switching feeds or on unmount

### Code Style
- Use `===` and `!==` instead of `==` and `!=`
- Use `Enum.empty?(list)` instead of `length(list) === 0`
- Predicate functions end with `?` (e.g., `valid?/1`), reserve `is_` prefix for guards only
- Start pipe chains with a raw value: `a |> b() |> c()` not `b(a) |> c()`
- Group aliases from the same parent module into a single statement: `alias MyApp.{Foo, Bar}` not separate `alias` lines
- Avoid single-letter variable names that are acronyms
- Section large context modules with comment headers (e.g., `# USERS`, `# SAVED USER VIEWS`)

### Aliasing Conventions
- **Never alias past namespace boundaries** — alias to the namespace, not the leaf module. This preserves context about where a module lives.
- Namespaces that must be preserved: `Support`, `Factory`, `Accounts`, `Deliveries`, `Channels`, `Handlers`, `Hooks`, `Topics`
- **Correct**: `alias NotificationPlatformPg.Support.Factory` then use `Factory.Accounts.User`
- **Incorrect**: `alias NotificationPlatformPg.Support.Factory.Accounts.User, as: UserFactory`
- The same applies to `Support.DataCase`, `Support.ConnCase`, `Hooks.UserAuth`, `Topics.Message`, etc.

### Configuration
- Every app with configurable values has a dedicated `Config` module using `Application.get_env` / `Application.fetch_env!`
- Config modules use an `@app` module attribute for the app name
- **Never** access `Application.*env` outside a Config module — all business logic reads config through the Config module
- **Never** use `Mix.env()` at runtime in production — use compile-time conditionals
- **Never** use `Application.put_env/3` in tests — use dependency injection
- **No `runtime.exs`** — all production config (including secrets via `System.fetch_env!`) lives in `prod.exs` (env vars available at Docker build time)

#### Config Module Pattern
```elixir
defmodule MyApp.Config do
  @app :my_app

  def my_setting do
    Application.get_env(@app, :my_setting, "default")
  end

  def my_secret do
    Application.fetch_env!(@app, :my_secret)
  end
end
```

#### Existing Config Modules
| App | Module |
|-----|--------|
| `notification_platform_auth_service` | `NotificationPlatformAuthService.Config` |
| `notification_platform_billing` | `NotificationPlatformBilling.Config` |
| `notification_platform_delivery_channels` | `NotificationPlatformDeliveryChannels.Config` |
| `notification_platform_mailer` | `NotificationPlatformMailer.Config` |
| `notification_platform_rate_limiting` | `NotificationPlatformRateLimiting.Config` |
| `notification_platform_rpc` | `NotificationPlatformRPC.Config` |
| `notification_platform_webhooks` | `NotificationPlatformWebhooks.Config` |

### Database Patterns
- Use `:utc_datetime_usec` for timestamp precision
- Add appropriate indexes for foreign keys and frequently queried fields
- **Never create a regular index on a column that is already the leading column of a unique/composite index** — the unique index already serves as the lookup index
- Use `on_conflict` with `conflict_target` for upserts

### Error Handling
- Use `ErrorMessage` library for structured errors with code, message, and details
- Return `{:ok, result}` or `{:error, ErrorMessage.t()}` from context functions
- Use `with` for chaining operations that may fail

## Umbrella Apps

### `notification_platform`
Core business logic and domain contexts.
- Depends on `notification_pg` for database access
- Contains `Phoenix.PubSub` server (`NotificationPlatform.PubSub`)
- Uses `DNSCluster` for node discovery

### `notification_platform_web`
Phoenix web layer with LiveView support.
- Uses `NotificationPlatformWeb` macros for controllers, live views, and components
- `use NotificationPlatformWeb, :live_view` for LiveView modules
- `use NotificationPlatformWeb, :controller` for controller modules
- Core components in `NotificationPlatformWeb.CoreComponents`
- Layouts in `NotificationPlatformWeb.Layouts`

### `notification_platform_rpc`
Remote Procedure Call utilities for distributed Elixir nodes.
- **`NotificationPlatformRPC.call/5`** - Synchronous RPC call with timeout (default 10s)
- **`NotificationPlatformRPC.cast/4`** - Asynchronous RPC cast (fire and forget)
- **`NotificationPlatformRPC.call_on_random_node/5`** - Call on a random node matching a filter string
  - Supports `retry?: true` option to retry when no nodes found
  - Supports `call_directly?: true` option to bypass RPC and call locally
- Uses `:erpc` under the hood with proper error handling
- Returns `ErrorMessage` structs for RPC errors (`:bad_request`, `:request_timeout`, `:service_unavailable`)
- **Return value normalization**: all non-status-tuple results are wrapped in `{:ok, result}` — this means `list_*` functions returning plain lists become `{:ok, list}` through service wrappers
- Configure `call_directly?: true` in `:notification_platform_rpc` config to bypass RPC in dev/test (normalization still applies)
- Depends on `shared_utils` for cluster utilities (`SharedUtils.Cluster.filter_nodes/1`)

### `notification_pub_sub`
PubSub utilities for broadcasting and subscribing to events across the application.
- **`NotificationPubSub.Message`** - Core message struct with `subscribe/2`, `unsubscribe/2`, `send_event/2`
- **`NotificationPubSub.Topics.*`** - Domain-specific topic modules
- See `apps/notification_pub_sub/AGENTS.md` for guidelines on creating new PubSub topics

### `shared_utils`
Shared utility modules used across the umbrella.
- **`SharedUtils.HTTP`** - HTTP client wrapper around Finch with connection pooling
  - Create custom HTTP clients by implementing the `new/1` callback
  - Use `SharedUtils.Support.HTTPSandbox` for test isolation
- **`SharedUtils.Cluster`** - Cluster utilities for node filtering and topology management
  - `filter_nodes/2` - Filter nodes by name pattern
  - `toplogy_supervisor/1` - LibCluster supervisor (disabled in test)
- **`SharedUtils.Logger`** - Structured logging with identifier prefixes
  - `SharedUtils.Logger.info("MyModule", "message")` → `[MyModule] message`
  - Supports `ErrorMessage` structs for formatted error logging
- **`SharedUtils.DateTime`** - DateTime parsing and manipulation utilities
- **`SharedUtils.Enum`** - Extended enum utilities
- **`SharedUtils.Map`** - Map transformation utilities
- **`SharedUtils.String`** - String manipulation utilities
- **`SharedUtils.Collection`** - Collection utilities

### `notification_platform_pg`
Database layer, shared Ecto schemas, and contexts for the notification platform.
- **`NotificationPlatformPg.Schema`** - Base schema macro providing `use Ecto.Schema`, `import Ecto.Changeset`, and `@type t`
- **`NotificationPlatformPg.Repo`** - Ecto repository using PostgreSQL adapter
- Schemas are organized under **context modules** (plural naming) in subdirectories
- All schemas use `:utc_datetime_usec` timestamps via `NotificationPlatformPg.Repo.default_options/1`
- Use `EctoShorts.Actions` for CRUD operations (find, all, create, update, delete, find_and_update, find_and_upsert)
- Prefer compound actions (`find_and_update`, `find_and_upsert`) over separate find + update calls
- PG contexts are the **sole API layer** for database access: `PG Context → Service Layer (RPC) → Web Layer`
- Schemas define `@required_fields` and `@available_fields` module attributes used in changesets

#### Schema Context Structure
| Context | Schemas | Description |
|---------|---------|-------------|
| `NotificationPlatformPg.Accounts` | `Accounts.User`, `Accounts.Organization`, `Accounts.ApiKey`, `Accounts.BillingDetails` | User, organization, API key, and billing management |
| `NotificationPlatformPg.Deliveries` | `Deliveries.Message` | Message delivery tracking |

#### Directory Structure
```
lib/notification_platform_pg/
├── accounts.ex                    # Context module with CRUD functions (users, orgs, api keys, billing)
├── accounts/
│   ├── api_key.ex                 # NotificationPlatformPg.Accounts.ApiKey schema
│   ├── billing_details.ex         # NotificationPlatformPg.Accounts.BillingDetails schema
│   ├── organization.ex            # NotificationPlatformPg.Accounts.Organization schema
│   └── user.ex                    # NotificationPlatformPg.Accounts.User schema
├── deliveries.ex                  # Context module
├── deliveries/
│   └── message.ex                 # NotificationPlatformPg.Deliveries.Message schema (UUID PK)
├── repo.ex                        # Ecto Repo
└── schema.ex                      # Shared schema macro
```

#### Factory Structure (test/support/factory/)
```
test/support/factory/
├── factory.ex                     # Namespace modules (Accounts, Deliveries)
├── accounts/
│   ├── api_key.ex
│   ├── billing_details.ex
│   ├── organization.ex
│   └── user.ex
└── deliveries/
    └── message.ex
```

### `notification_platform_service`
Account management and delivery orchestration service. Contains business logic and wraps PG context calls via RPC for the web layer.
- **`NotificationPlatformService`** - RPC wrapper — public API called by the web layer
  - `register_user/1` - Atomic registration (org + user + membership + billing) via `RegistrationManager`
  - `list_messages/2`, `count_messages_by_status/1` - Delivery queries via RPC
  - `enqueue_message/1` - Enqueue delivery job via `NotificationPlatformDeliveryChannels`
- **`NotificationPlatformService.RegistrationManager`** - Ecto.Multi registration logic
  - Creates organization, user, membership, and billing details atomically
  - Normalizes Ecto.Multi 4-tuple errors to standard `{:error, ErrorMessage.t()}` for RPC compatibility
- Dependencies: `notification_platform_pg`, `notification_platform_rpc`, `notification_platform_delivery_channels`

### `notification_platform_delivery_channels`
Multi-channel notification delivery system with unified abstraction.
- **`NotificationPlatformDeliveryChannels.DeliveryChannel`** - Behaviour defining channel interface:
  - `channel_type/0` - Returns atom identifying the channel
  - `validate_config/1` - Validates channel configuration
  - `build_message/1` - Builds channel-specific message from params
  - `deliver/2` - Delivers message using channel provider
- **`NotificationPlatformDeliveryChannels.Channels`** - Channel registry
  - `get/1` - Get channel module by type atom
  - `get!/1` - Get channel module or return `{:error, ErrorMessage.t()}`
  - `available/0` - List available channel types
- **`NotificationPlatformDeliveryChannels.HTTP`** - App-specific HTTP client wrapping `SharedUtils.HTTP`
  - Started in application supervision tree
  - Provides `get/3`, `post/4`, `put/4`, `delete/3` with dedicated connection pool
- **`NotificationPlatformDeliveryChannels.SendWorker`** - Oban worker for message delivery
  - Queue: `:messages`, max attempts: 5
  - Idempotent design - checks message status before processing
  - Broadcasts status changes via `NotificationPubSub`
- **Channel Implementations**:
  - `Channels.Email` - Uses `NotificationPlatformMailer.SES`
  - `Channels.Slack` - Uses Slack Web API via `NotificationPlatformDeliveryChannels.HTTP`
  - `Channels.Discord` - Uses Discord webhooks via `NotificationPlatformDeliveryChannels.HTTP`
  - `Channels.SMS` - Uses Twilio REST API via `NotificationPlatformDeliveryChannels.HTTP`

### `notification_platform_webhooks`
Webhook handling for external providers (Stripe, SES).
- **`NotificationPlatformWebhooks.WebhookHandler`** - Behaviour defining webhook handler interface:
  - `verify_signature/3` - Verifies webhook signature from provider
  - `parse_event/1` - Parses raw payload into event map
  - `handle_event/2` - Handles specific event type with data
- **`NotificationPlatformWebhooks.Handlers`** - Handler registry
  - `get/1` - Get handler module by provider string
  - `get!/1` - Get handler module or return `{:error, ErrorMessage.t()}`
  - `available/0` - List available provider strings
- **`NotificationPlatformWebhooks.BillingBehaviour`** - Contract for billing module integration
  - `activate_from_checkout/2` - Activate subscription from Stripe checkout
  - `handle_webhook_event/2` - Handle billing-related webhook events
- **Handler Implementations**:
  - `Handlers.Stripe` - Stripe webhook handler using `Stripe.Webhook.construct_event/3`
    - Handles: `checkout.session.completed`, `invoice.payment_succeeded`, `invoice.payment_failed`, `customer.subscription.updated`, `customer.subscription.deleted`
    - Delegates to `NotificationPlatformBilling` (configurable via `:billing_module` compile-time config)
  - `Handlers.SES` - AWS SES bounce/complaint handler (placeholder for future)
- **Testing**: Use `NotificationPlatformWebhooks.Support.MockBilling` in test config for Stripe handler tests

### Primary Key Strategy
- **Integer primary keys** (`bigserial`) for: organizations, users, api_keys, slack_channels, discord_channels, organization_memberships
- **UUID primary keys** (`binary_id`) for: messages (high-throughput, distributed generation, partitioning support)
- Configure via `@primary_key {:id, :binary_id, autogenerate: true}` for UUID schemas

### Command Execution
- **Never** use shell pipes (`|`), redirects (`2>&1`), or output manipulation (`tail`, `head`, `grep`) when running commands
- Always run commands cleanly and directly (e.g., `mix test`, not `mix test 2>&1 | tail -5`)
- Run `mix coveralls` from the umbrella root to get coverage across all apps at once

### Service App Pattern
Apps that have a corresponding `_service` app must **never** be accessed directly by other apps in the cluster. Always go through the `_service` wrapper.

| Service App | Wraps | Description |
|-------------|-------|-------------|
| `NotificationPlatformBillingService` | `NotificationPlatformBilling` | Distributed billing operations via RPC |
| `NotificationPlatformAuthService` | `NotificationPlatformAuth` | Distributed auth operations via RPC |
| `NotificationPlatformService` | `NotificationPlatformPg`, `NotificationPlatformDeliveryChannels` | Account management, registration, delivery orchestration via RPC |

**Rules:**
- **Never** depend on `notification_platform_billing` directly from another app — use `notification_platform_billing_service`
- **Never** depend on `notification_platform_auth` directly from another app — use `notification_platform_auth_service`
- The only apps that may reference the implementation module directly are the implementation app itself and its corresponding `_service` app
- If a new domain app needs distributed access, create a `_service` app following this pattern

### Testing Stripe Interactions
- Do **not** mock Stripe at the module level (e.g., swapping modules via `Application.compile_env`)
- Use [stripe-mock](https://github.com/stripe/stripe-mock) — a local HTTP server that implements the Stripe API
- Point `stripity_stripe` at the local stripe-mock server in test config
- This gives realistic end-to-end testing of Stripe interactions without hitting the real API
