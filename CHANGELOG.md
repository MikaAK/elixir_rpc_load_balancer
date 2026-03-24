## 0.2.1

### Features
- Add `CallDirect` selection algorithm for local-node execution without `:erpc` overhead
- Add `Drainer` module for graceful connection draining with in-flight call tracking
- Add `IndexRegistry` for lock-free index allocation using `:atomics` and `:persistent_term`
- Add `Retry` module with configurable retry logic for RPC operations
- Add `Config` module for centralized application configuration defaults
- Add `ValueCache` backed by `Cache.PersistentTerm`
- Add `call_directly?` option to `call/5`, `cast/5`, `call_on_random_node/5`, and `cast_on_random_node/5`
- Add `select_node/2` to the public API

### Refactors
- Consolidate cache initialization into `RpcLoadBalancer` supervisor
- Extract retry logic from `LoadBalancer` into dedicated `Retry` module
- Simplify selection algorithms (`LeastConnections`, `PowerOfTwo`, `RoundRobin`, `WeightedRoundRobin`) by leveraging shared caches
- Promote `RpcLoadBalancer` to a `Supervisor` managing caches and the load balancer GenServer

### Docs
- Add `testing-with-call-direct` how-to guide
- Update architecture docs, reference docs, and getting started tutorial for new API

## 0.1.0
- Initial Release
