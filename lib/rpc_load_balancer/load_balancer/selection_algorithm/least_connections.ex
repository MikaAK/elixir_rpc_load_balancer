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
  def init(load_balancer_name, opts) do
    nodes = Keyword.get(opts, :nodes, [])
    Enum.each(nodes, &ensure_counter(load_balancer_name, &1))
    :ok
  end

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, _opts \\ []) do
    node =
      node_list
      |> Enum.map(fn node -> {node, get_connection_count(load_balancer_name, node)} end)
      |> Enum.min_by(&elem(&1, 1))
      |> elem(0)

    increment_connections(load_balancer_name, node)
    node
  end

  @impl true
  def on_node_change(load_balancer_name, {:joined, nodes}) do
    Enum.each(nodes, &ensure_counter(load_balancer_name, &1))
    :ok
  end

  def on_node_change(load_balancer_name, {:left, nodes}) do
    Enum.each(nodes, &delete_counter(load_balancer_name, &1))
    :ok
  end

  @impl true
  def release_node(load_balancer_name, node) do
    decrement_connections(load_balancer_name, node)
    :ok
  end

  defp get_connection_count(load_balancer_name, node) do
    case CounterCache.lookup({:connections, load_balancer_name, node}) do
      [{_key, count}] -> count
      [] -> 0
    end
  end

  defp increment_connections(load_balancer_name, node) do
    CounterCache.update_counter(
      {:connections, load_balancer_name, node},
      {2, 1},
      {{:connections, load_balancer_name, node}, 0}
    )
  end

  defp decrement_connections(load_balancer_name, node) do
    CounterCache.update_counter(
      {:connections, load_balancer_name, node},
      {2, -1},
      {{:connections, load_balancer_name, node}, 0}
    )
  end

  defp ensure_counter(load_balancer_name, node) do
    CounterCache.insert_new({{:connections, load_balancer_name, node}, 0})
  end

  defp delete_counter(load_balancer_name, node) do
    CounterCache.delete({:connections, load_balancer_name, node})
  end
end
