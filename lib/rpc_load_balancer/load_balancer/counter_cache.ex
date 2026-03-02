defmodule RpcLoadBalancer.LoadBalancer.CounterCache do
  use Cache,
    adapter: Cache.ETS,
    name: :rpc_load_balancer_counter_cache,
    sandbox?: false,
    opts: [read_concurrency: true, write_concurrency: true]
end
