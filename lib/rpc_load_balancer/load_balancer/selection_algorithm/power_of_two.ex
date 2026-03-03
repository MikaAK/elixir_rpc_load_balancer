defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.PowerOfTwo do
  @moduledoc """
  Power of Two Choices node selection algorithm.

  Picks two random nodes and selects the one with fewer active connections.
  Provides a good balance between simplicity and load distribution without
  the overhead of scanning all nodes like Least Connections.

  Uses the same connection counter infrastructure as `LeastConnections`.
  `release_node/2` must be called when calls complete.
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
  def choose_from_nodes(load_balancer_name, node_list, opts \\ [])

  def choose_from_nodes(load_balancer_name, [node], _opts) do
    _ = increment_connections(load_balancer_name, node)
    node
  end

  def choose_from_nodes(load_balancer_name, node_list, _opts) do
    [candidate_a, candidate_b] = Enum.take_random(node_list, 2)

    count_a = get_connection_count(load_balancer_name, candidate_a)
    count_b = get_connection_count(load_balancer_name, candidate_b)

    chosen = if count_a <= count_b, do: candidate_a, else: candidate_b
    _ = increment_connections(load_balancer_name, chosen)
    chosen
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
    _ = decrement_connections(load_balancer_name, node)
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
