defmodule RpcLoadBalancer.LoadBalancer.DrainerCache do
  @moduledoc """
  Shared atomic counter for tracking in-flight calls per load balancer.
  """

  alias RpcLoadBalancer.LoadBalancer.IndexRegistry

  @cache_name :rpc_lb_drainer_cache

  use Cache,
    adapter: Cache.Counter,
    name: @cache_name,
    sandbox?: false,
    opts: [initial_size: 256]

  @spec register(atom()) :: non_neg_integer()
  def register(load_balancer_name) do
    IndexRegistry.get_or_register(@cache_name, load_balancer_name)
  end

  @spec count(non_neg_integer()) :: non_neg_integer()
  def count(index) do
    {:ok, count} = get(index)
    count || 0
  end
end
