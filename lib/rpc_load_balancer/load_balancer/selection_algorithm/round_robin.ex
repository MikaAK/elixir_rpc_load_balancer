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
  def choose_from_nodes(load_balancer_name, node_list, _opts \\ []) do
    count = CounterCache.get_and_increment(load_balancer_name, @counter_slot)
    _ = maybe_reset_count(load_balancer_name, count)
    Enum.at(node_list, rem(count - 1, length(node_list)))
  end

  defp maybe_reset_count(load_balancer_name, count) when count > 10_000_000 do
    CounterCache.reset_counter(load_balancer_name, @counter_slot)
  end

  defp maybe_reset_count(_load_balancer_name, _count), do: :ok
end
