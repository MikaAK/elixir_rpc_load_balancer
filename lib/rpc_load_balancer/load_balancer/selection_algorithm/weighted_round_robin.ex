defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.WeightedRoundRobin do
  @moduledoc """
  Weighted round robin node selection algorithm.

  Accepts a weight map via `algorithm_opts` where keys are node names and
  values are positive integers representing relative capacity. Nodes with
  higher weights receive proportionally more traffic.

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

  @impl true
  def init(load_balancer_name, opts) do
    weights = Keyword.get(opts, :weights, %{})
    CounterCache.insert_raw({{:weights, load_balancer_name}, weights})
    :ok
  end

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, _opts \\ []) do
    weights = get_weights(load_balancer_name)
    expanded = expand_node_list(node_list, weights)
    count = increment_and_get(load_balancer_name)
    _ = maybe_reset_count(load_balancer_name, count)
    Enum.at(expanded, rem(count - 1, length(expanded)))
  end

  defp expand_node_list(node_list, weights) do
    Enum.flat_map(node_list, fn node ->
      weight = Map.get(weights, node, 1)
      List.duplicate(node, weight)
    end)
  end

  defp get_weights(load_balancer_name) do
    case CounterCache.lookup({:weights, load_balancer_name}) do
      [{_key, weights}] -> weights
      [] -> %{}
    end
  end

  defp maybe_reset_count(load_balancer_name, count) when count > 10_000_000 do
    _ =
      CounterCache.update_counter(
        {:weighted_counter, load_balancer_name},
        {2, -count},
        {{:weighted_counter, load_balancer_name}, 0}
      )

    :ok
  end

  defp maybe_reset_count(_load_balancer_name, _count), do: :ok

  defp increment_and_get(load_balancer_name) do
    CounterCache.update_counter(
      {:weighted_counter, load_balancer_name},
      {2, 1},
      {{:weighted_counter, load_balancer_name}, 0}
    )
  end
end
