defmodule RpcLoadBalancer.LoadBalancer.LoadBalancerOptsCache do
  @moduledoc """
  Cache for parsed, immutable per-load-balancer options.

  Algorithms with configurable options (`LeastCpu`, `WeightedRoundRobin`,
  `HashRing`) call `init/2` once during boot and stash the parsed config
  here so subsequent `choose_from_nodes` calls don't re-parse keyword
  lists on every selection.

  Backed by `Cache.PersistentTerm` because entries are written once at
  boot and read on every selection — exactly the access pattern
  `:persistent_term` is designed for. Mutable runtime state (e.g. the
  hash ring rebuilt on every node-change event) lives in dedicated
  ETS-backed caches instead.
  """

  use Cache,
    adapter: Cache.PersistentTerm,
    name: :rpc_lb_opts_cache,
    sandbox?: Mix.env() === :test,
    opts: []
end
