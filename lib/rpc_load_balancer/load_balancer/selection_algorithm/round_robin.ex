defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.RoundRobin do
  @moduledoc """
  Round robin node selection algorithm.

  Uses an atomic ETS counter to cycle through nodes. The counter is
  incremented and read in a single `update_counter` call to
  avoid race conditions under concurrent access.
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  alias RpcLoadBalancer.LoadBalancer.CounterCache

  @counter_slot 1

  @impl true
  def init(load_balancer_name, _opts) do
    CounterCache.register(load_balancer_name, @counter_slot)
    :ok
  end

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, _opts \\ []) do
    index = CounterCache.register(load_balancer_name, @counter_slot)
    count = CounterCache.get_and_increment(index)
    _ = maybe_reset_count(index, count)
    Enum.at(node_list, rem(count - 1, length(node_list)))
  end

  defp maybe_reset_count(index, count) when count > 10_000_000 do
    CounterCache.reset_counter(index)
  end

  defp maybe_reset_count(_index, _count), do: :ok
end
