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

  @cache_name :rpc_lb_opts_cache

  use Cache,
    adapter: Cache.PersistentTerm,
    name: @cache_name,
    sandbox?: Mix.env() === :test,
    opts: []

  @doc """
  Hot-path reader that bypasses the telemetry wrapper.

  Calls the configured cache adapter directly so algorithms that look
  up parsed options on every selection (e.g. `HashRing` ring weight,
  `LeastCpu` thresholds) don't pay telemetry-span overhead for what
  is functionally a constant.
  """
  @spec read(term()) :: term() | nil
  def read(key) do
    case cache_adapter().get(@cache_name, key) do
      {:ok, nil} -> nil
      {:ok, value} -> Cache.TermEncoder.decode(value)
      _ -> nil
    end
  end
end
