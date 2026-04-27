defmodule RpcLoadBalancer.LoadBalancer.ValueCache do
  use Cache,
    adapter: Cache.PersistentTerm,
    name: :rpc_lb_value_cache,
    sandbox?: Mix.env() === :test,
    opts: []
end
