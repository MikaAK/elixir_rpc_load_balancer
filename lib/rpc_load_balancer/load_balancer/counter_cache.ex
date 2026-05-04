defmodule RpcLoadBalancer.LoadBalancer.CounterCache do
  @moduledoc """
  Shared atomic counters for slot-based round-robin and
  per-node connection tracking across all load balancers.
  """

  alias RpcLoadBalancer.LoadBalancer.IndexRegistry

  @cache_name :rpc_lb_counter_cache
  @counter_ref_pt_key {:rpc_lb_counter_cache, :__counter_ref__}

  use Cache,
    adapter: Cache.Counter,
    name: @cache_name,
    sandbox?: false,
    opts: [initial_size: 1024]

  @doc """
  Returns the underlying `:counters` reference for the shared counter cache.

  Hot-path callers cache this once per selection (or per process) and
  use `:counters.get/2` / `:counters.add/3` directly instead of paying
  the `:telemetry.span/3` overhead of `Cache.get/1` per read.
  """
  @spec counter_ref() :: :counters.counters_ref()
  def counter_ref do
    :persistent_term.get(@counter_ref_pt_key)
  end

  @spec register(atom(), pos_integer()) :: non_neg_integer()
  def register(load_balancer_name, slot_id) do
    IndexRegistry.get_or_register(@cache_name, {:slot, load_balancer_name, slot_id})
  end

  @doc """
  Lookup of a node's connection count without telemetry overhead.

  Returns 0 for nodes that haven't been registered yet so callers can
  use a missing entry as the natural "lowest" candidate.
  """
  @spec lookup_node_count(atom(), node()) :: non_neg_integer()
  def lookup_node_count(load_balancer_name, node) do
    case IndexRegistry.lookup_index(@cache_name, {:conn, load_balancer_name, node}) do
      nil -> 0
      index -> :counters.get(counter_ref(), index + 1)
    end
  end

  @spec get_and_increment(non_neg_integer()) :: non_neg_integer()
  def get_and_increment(index) do
    :ok = increment(index)
    {:ok, count} = get(index)
    count || 0
  end

  @spec reset_counter(non_neg_integer()) :: :ok
  def reset_counter(index) do
    delete(index)
  end

  @spec register_node(atom(), node()) :: non_neg_integer()
  def register_node(load_balancer_name, node) do
    IndexRegistry.get_or_register(@cache_name, {:conn, load_balancer_name, node})
  end

  @spec increment_node(atom(), node()) :: :ok
  def increment_node(load_balancer_name, node) do
    increment(register_node(load_balancer_name, node))
  end

  @spec decrement_node(atom(), node()) :: :ok
  def decrement_node(load_balancer_name, node) do
    decrement(register_node(load_balancer_name, node))
  end

  @spec get_node_count(atom(), node()) :: non_neg_integer()
  def get_node_count(load_balancer_name, node) do
    {:ok, count} = get(register_node(load_balancer_name, node))
    count || 0
  end

  @spec erase_node_counter(atom(), node()) :: :ok
  def erase_node_counter(load_balancer_name, node) do
    delete(register_node(load_balancer_name, node))
  end
end
