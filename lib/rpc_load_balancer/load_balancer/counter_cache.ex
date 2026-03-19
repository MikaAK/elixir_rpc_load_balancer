defmodule RpcLoadBalancer.LoadBalancer.CounterCache do
  @moduledoc """
  Shared atomic counters for slot-based round-robin and
  per-node connection tracking across all load balancers.
  """

  use Cache,
    adapter: Cache.Counter,
    name: :rpc_lb_counter_cache,
    sandbox?: false,
    opts: [initial_size: 1024]

  @spec get_and_increment(atom(), pos_integer()) :: integer()
  def get_and_increment(load_balancer_name, index) do
    key = {:slot, load_balancer_name, index}
    :ok = increment(key)
    {:ok, count} = get(key)
    count
  end

  @spec reset_counter(atom(), pos_integer()) :: :ok
  def reset_counter(load_balancer_name, index) do
    delete({:slot, load_balancer_name, index})
  end

  @spec increment_node(atom(), node()) :: :ok
  def increment_node(load_balancer_name, node) do
    increment({:conn, load_balancer_name, node})
  end

  @spec decrement_node(atom(), node()) :: :ok
  def decrement_node(load_balancer_name, node) do
    decrement({:conn, load_balancer_name, node})
  end

  @spec get_node_count(atom(), node()) :: integer()
  def get_node_count(load_balancer_name, node) do
    {:ok, count} = get({:conn, load_balancer_name, node})
    count
  end

  @spec erase_node_counter(atom(), node()) :: :ok
  def erase_node_counter(load_balancer_name, node) do
    delete({:conn, load_balancer_name, node})
  end
end
