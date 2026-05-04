defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobin do
  @moduledoc """
  Weighted round robin node selection algorithm.

  Accepts a weight map via `algorithm_opts` where keys are node names and
  values are positive integers representing relative capacity. Nodes with
  higher weights receive proportionally more traffic.

  The expanded node list — node names duplicated according to weight —
  is cached in `:persistent_term` keyed by the load balancer's running
  node membership. The cache is rebuilt only when membership changes,
  so the steady-state hot path is `Enum.at/2` on the cached list plus
  one atomic counter increment.

  ## Usage

      RpcLoadBalancer.LoadBalancer.start_link(
        name: :my_balancer,
        selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobin,
        algorithm_opts: [weights: %{:"node1@host" => 3, :"node2@host" => 1}]
      )

  Nodes not present in the weight map receive a default weight of 1.
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  alias RpcLoadBalancer.LoadBalancer.CounterCache
  alias RpcLoadBalancer.LoadBalancer.LoadBalancerOptsCache

  @counter_slot 2

  @impl true
  def init(load_balancer_name, opts) do
    weights = Keyword.get(opts, :weights, %{})
    CounterCache.register(load_balancer_name, @counter_slot)
    LoadBalancerOptsCache.put({load_balancer_name, :weights}, nil, weights)
    erase_expanded(load_balancer_name)
    :ok
  end

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, _opts \\ []) do
    expanded = get_or_build_expanded(load_balancer_name, node_list)
    index = CounterCache.register(load_balancer_name, @counter_slot)
    count = CounterCache.get_and_increment(index)
    _ = maybe_reset_count(index, count)
    Enum.at(expanded, rem(count - 1, length(expanded)))
  end

  @impl true
  def on_node_change(load_balancer_name, {_event, _nodes}) do
    erase_expanded(load_balancer_name)
    :ok
  end

  defp get_or_build_expanded(load_balancer_name, node_list) do
    case :persistent_term.get(expanded_pt_key(load_balancer_name), nil) do
      {^node_list, expanded} ->
        expanded

      _ ->
        build_expanded(load_balancer_name, node_list)
    end
  end

  defp build_expanded(load_balancer_name, node_list) do
    weights = get_weights(load_balancer_name)
    expanded = expand_node_list(node_list, weights)
    :persistent_term.put(expanded_pt_key(load_balancer_name), {node_list, expanded})
    expanded
  end

  defp erase_expanded(load_balancer_name) do
    _ = :persistent_term.erase(expanded_pt_key(load_balancer_name))
    :ok
  end

  defp expanded_pt_key(load_balancer_name), do: {__MODULE__, load_balancer_name}

  defp expand_node_list(node_list, weights) do
    Enum.flat_map(node_list, fn node ->
      weight = Map.get(weights, node, 1)
      List.duplicate(node, weight)
    end)
  end

  defp get_weights(load_balancer_name) do
    case LoadBalancerOptsCache.lookup({load_balancer_name, :weights}) do
      nil -> %{}
      weights -> weights
    end
  end

  defp maybe_reset_count(index, count) when count > 10_000_000 do
    CounterCache.reset_counter(index)
  end

  defp maybe_reset_count(_index, _count), do: :ok
end
