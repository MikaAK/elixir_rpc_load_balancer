defmodule RpcLoadBalancer.LoadBalancer.AlgorithmCache do
  use Cache,
    adapter: Cache.ETS,
    name: :rpc_load_balancer_algorithm_cache,
    sandbox?: false,
    opts: [read_concurrency: true, write_concurrency: true]
end
