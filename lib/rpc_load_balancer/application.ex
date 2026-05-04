defmodule RpcLoadBalancer.Application do
  @moduledoc false

  use Application

  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  # Caches every load balancer relies on regardless of algorithm.
  @core_caches [
    RpcLoadBalancer.LoadBalancer.AlgorithmCache,
    RpcLoadBalancer.LoadBalancer.CounterCache,
    RpcLoadBalancer.LoadBalancer.DrainerCache,
    RpcLoadBalancer.LoadBalancer.IndexRegistry,
    RpcLoadBalancer.LoadBalancer.LoadBalancerOptsCache
  ]

  # Algorithms whose `caches/0` declarations contribute to the
  # application's Cache supervisor. Algorithms not in this list still
  # work, but their caches won't be started — add them here when their
  # caches need to be live before any load balancer using them boots.
  @known_algorithms [
    RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.CallDirect,
    RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing,
    RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastConnections,
    RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu,
    RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.PowerOfTwo,
    RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.Random,
    RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin,
    RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobin
  ]

  @impl true
  def start(_type, _args) do
    children = [
      {Cache, @core_caches ++ SelectionAlgorithm.all_caches(@known_algorithms)},
      RpcLoadBalancer.LoadBalancer.Pg
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RpcLoadBalancer.Supervisor)
  end
end
