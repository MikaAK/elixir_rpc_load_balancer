defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastConnections do
  @moduledoc """
  Least connections node selection algorithm.

  Tracks active connection counts per node using ETS counters and always
  selects the node with the fewest active connections. When a call completes,
  `release_node/2` must be called to decrement the counter. The convenience
  API in `RpcLoadBalancer.LoadBalancer.call/5` handles this automatically.
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  alias RpcLoadBalancer.LoadBalancer.CounterCache

  @impl true
  def init(_load_balancer_name, _opts), do: :ok

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, _opts \\ []) do
    node =
      node_list
      |> Enum.map(fn node -> {node, CounterCache.get_node_count(load_balancer_name, node)} end)
      |> Enum.min_by(&elem(&1, 1))
      |> elem(0)

    CounterCache.increment_node(load_balancer_name, node)
    node
  end

  @impl true
  def on_node_change(_load_balancer_name, {:joined, _nodes}), do: :ok

  def on_node_change(load_balancer_name, {:left, nodes}) do
    Enum.each(nodes, &CounterCache.erase_node_counter(load_balancer_name, &1))
    :ok
  end

  @impl true
  def release_node(load_balancer_name, node) do
    CounterCache.decrement_node(load_balancer_name, node)
    :ok
  end
end
