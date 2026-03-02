defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing do
  @moduledoc """
  Consistent hash ring node selection algorithm.

  Routes requests to nodes based on a caller-provided `:key` option.
  Uses `:erlang.phash2/2` for distribution across the node list.
  When no key is provided, falls back to random selection.

  ## Usage

      RpcLoadBalancer.LoadBalancer.select_node(:my_balancer, key: "user:123")
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  @impl true
  def choose_from_nodes(_load_balancer_name, node_list, opts \\ []) do
    case Keyword.get(opts, :key) do
      nil ->
        Enum.random(node_list)

      key ->
        sorted_nodes = Enum.sort(node_list)
        index = :erlang.phash2(key, length(sorted_nodes))
        Enum.at(sorted_nodes, index)
    end
  end
end
