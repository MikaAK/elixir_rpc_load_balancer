defmodule RpcLoadBalancer.LoadBalancer.CounterCache do
  @moduledoc """
  Per-load-balancer atomic counters for slot-based round-robin and
  per-node connection tracking.

  Each load balancer gets its own `Cache.Counter` instance with
  `initial_size: 64`, avoiding hash collisions between load balancers.
  """

  @spec cache_name(atom()) :: atom()
  def cache_name(load_balancer_name), do: :"#{load_balancer_name}_counter_cache"

  @spec child_spec(atom()) :: Supervisor.child_spec()
  def child_spec(load_balancer_name) do
    Cache.Counter.child_spec({cache_name(load_balancer_name), [initial_size: 64]})
  end

  @spec get_and_increment(atom(), pos_integer()) :: integer()
  def get_and_increment(load_balancer_name, index) do
    name = cache_name(load_balancer_name)
    key = {:slot, index}
    :ok = Cache.Counter.increment(name, key)
    {:ok, count} = Cache.Counter.get(name, key)
    count
  end

  @spec reset_counter(atom(), pos_integer()) :: :ok
  def reset_counter(load_balancer_name, index) do
    Cache.Counter.delete(cache_name(load_balancer_name), {:slot, index})
  end

  @spec increment_node(atom(), node()) :: :ok
  def increment_node(load_balancer_name, node) do
    Cache.Counter.increment(cache_name(load_balancer_name), {:conn, node})
  end

  @spec decrement_node(atom(), node()) :: :ok
  def decrement_node(load_balancer_name, node) do
    Cache.Counter.decrement(cache_name(load_balancer_name), {:conn, node})
  end

  @spec get_node_count(atom(), node()) :: integer()
  def get_node_count(load_balancer_name, node) do
    {:ok, count} = Cache.Counter.get(cache_name(load_balancer_name), {:conn, node})
    count
  end

  @spec erase_node_counter(atom(), node()) :: :ok
  def erase_node_counter(load_balancer_name, node) do
    Cache.Counter.delete(cache_name(load_balancer_name), {:conn, node})
  end
end
