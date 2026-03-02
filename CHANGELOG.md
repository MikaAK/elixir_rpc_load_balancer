## 0.2.0

- Refactor LoadBalancer GenServer to use `handle_continue` for initialization
- Extend `SelectionAlgorithm` behaviour with `init/2`, `on_node_change/2`, `release_node/2` lifecycle callbacks
- Fix Round Robin race condition with atomic `update_counter` (single call instead of separate read + write)
- Replace string cache keys with tuple keys for better performance
- Add new selection algorithms: LeastConnections, PowerOfTwo, HashRing, WeightedRoundRobin
- Add convenience `LoadBalancer.call/5` and `LoadBalancer.cast/5` API
- Add `:pg` membership monitoring via `on_node_change` callbacks
- Add `algorithm_opts` support for configurable algorithms
- Switch `elixir_cache` to `ets-rehydration` branch for ETS function support
- Remove misplaced ErrorMessage tests and docs

## 0.1.0
- Initial Release
