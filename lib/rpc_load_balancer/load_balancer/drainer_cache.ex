defmodule RpcLoadBalancer.LoadBalancer.DrainerCache do
  @moduledoc """
  Per-load-balancer atomic counter for tracking in-flight calls.

  Each load balancer gets its own `Cache.Counter` instance with a single
  slot, so there are no hash collisions between load balancers.
  """

  @key :drainer

  @spec cache_name(atom()) :: atom()
  def cache_name(load_balancer_name), do: :"#{load_balancer_name}_drainer_cache"

  @spec child_spec(atom()) :: Supervisor.child_spec()
  def child_spec(load_balancer_name) do
    Cache.Counter.child_spec({cache_name(load_balancer_name), [initial_size: 1]})
  end

  @spec increment(atom()) :: :ok
  def increment(load_balancer_name) do
    Cache.Counter.increment(cache_name(load_balancer_name), @key)
  end

  @spec decrement(atom()) :: :ok
  def decrement(load_balancer_name) do
    Cache.Counter.decrement(cache_name(load_balancer_name), @key)
  end

  @spec count(atom()) :: integer()
  def count(load_balancer_name) do
    {:ok, count} = Cache.Counter.get(cache_name(load_balancer_name), @key)
    count
  end
end
