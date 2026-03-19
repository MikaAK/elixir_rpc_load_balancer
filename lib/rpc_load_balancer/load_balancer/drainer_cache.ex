defmodule RpcLoadBalancer.LoadBalancer.DrainerCache do
  @moduledoc """
  Shared atomic counter for tracking in-flight calls per load balancer.
  """

  use Cache,
    adapter: Cache.Counter,
    name: :rpc_lb_drainer_cache,
    sandbox?: false,
    opts: [initial_size: 256]

  @spec count(atom()) :: integer()
  def count(load_balancer_name) do
    {:ok, count} = get(load_balancer_name)
    count
  end
end
