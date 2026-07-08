defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobin do
  @moduledoc """
  Weighted round robin node selection algorithm.

  Accepts a weight map via `algorithm_opts` where keys are node names and
  values are positive integers representing relative capacity. Nodes with
  higher weights receive proportionally more traffic.

  Storage:
    * `:weights` (set once at `init/2`) lives in `:persistent_term`
      keyed by `{__MODULE__, lb_name, :weights}`.
    * The expanded node list (the weight map projected into a flat
      list, one entry per weight unit) lives in `WeightedRoundRobinCache`
      (ETS). It's rebuilt on every `on_node_change` so storing it in PT
      would trigger continuous global GC in clusters with steady
      flapping; ETS writes are local and lock-free under
      `write_concurrency: true`.

  Steady-state hot path is one ETS lookup, one atomic counter
  increment, and an `Enum.at/2` into the cached expanded list.

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
  alias RpcLoadBalancer.LoadBalancer.WeightedRoundRobinCache

  @counter_slot 2

  @impl true
  def caches, do: [WeightedRoundRobinCache]

  @impl true
  def init(load_balancer_name, opts) do
    weights = Keyword.get(opts, :weights, %{})
    CounterCache.register(load_balancer_name, @counter_slot)
    :persistent_term.put(weights_pt_key(load_balancer_name), weights)
    WeightedRoundRobinCache.delete_expanded(load_balancer_name)
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
    WeightedRoundRobinCache.delete_expanded(load_balancer_name)
    :ok
  end

  defp get_or_build_expanded(load_balancer_name, node_list) do
    case WeightedRoundRobinCache.get_expanded(load_balancer_name) do
      {^node_list, expanded} -> expanded
      _ -> build_expanded(load_balancer_name, node_list)
    end
  end

  defp build_expanded(load_balancer_name, node_list) do
    weights = get_weights(load_balancer_name)
    expanded = expand_node_list(node_list, weights)
    WeightedRoundRobinCache.put_expanded(load_balancer_name, node_list, expanded)
    expanded
  end

  defp weights_pt_key(load_balancer_name), do: {__MODULE__, load_balancer_name, :weights}

  defp get_weights(load_balancer_name) do
    :persistent_term.get(weights_pt_key(load_balancer_name), %{})
  end

  defp expand_node_list(node_list, weights) do
    Enum.flat_map(node_list, fn node ->
      weight = Map.get(weights, node, 1)
      List.duplicate(node, weight)
    end)
  end

  defp maybe_reset_count(index, count) when count > 10_000_000 do
    CounterCache.reset_counter(index)
  end

  defp maybe_reset_count(_index, _count), do: :ok
end
