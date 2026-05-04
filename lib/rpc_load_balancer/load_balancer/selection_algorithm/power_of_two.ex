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
  def init(_load_balancer_name, _opts), do: :ok

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, opts \\ [])

  def choose_from_nodes(load_balancer_name, [node], _opts) do
    CounterCache.increment_node(load_balancer_name, node)
    node
  end

  def choose_from_nodes(load_balancer_name, node_list, _opts) do
    [candidate_a, candidate_b] = Enum.take_random(node_list, 2)

    count_a = CounterCache.read_node_count(load_balancer_name, candidate_a)
    count_b = CounterCache.read_node_count(load_balancer_name, candidate_b)

    chosen = if count_a <= count_b, do: candidate_a, else: candidate_b
    CounterCache.increment_node(load_balancer_name, chosen)
    chosen
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
