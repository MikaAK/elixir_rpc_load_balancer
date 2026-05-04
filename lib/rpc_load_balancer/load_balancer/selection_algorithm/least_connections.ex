defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastConnections do
  @moduledoc """
  Least connections node selection algorithm.

  Tracks active connection counts per node using ETS counters and always
  selects the node with the fewest active connections. When a call completes,
  `release_node/2` must be called to decrement the counter. The convenience
  API in `RpcLoadBalancer.LoadBalancer.call/5` handles this automatically.

  Hot-path implementation uses `CounterCache.read_node_count/2` (which
  bypasses the telemetry wrapper) and a single-pass `Enum.reduce/3` that
  allocates one tuple instead of building an intermediate list.
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  alias RpcLoadBalancer.LoadBalancer.CounterCache

  @impl true
  def init(_load_balancer_name, _opts), do: :ok

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, opts \\ [])

  def choose_from_nodes(load_balancer_name, [single_node], _opts) do
    CounterCache.increment_node(load_balancer_name, single_node)
    single_node
  end

  def choose_from_nodes(load_balancer_name, [first | rest], _opts) do
    chosen = pick_least_loaded(load_balancer_name, first, rest)
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

  defp pick_least_loaded(load_balancer_name, first, rest) do
    initial_count = CounterCache.read_node_count(load_balancer_name, first)

    {best_node, _best_count} =
      Enum.reduce(rest, {first, initial_count}, fn node, {_best_node, best_count} = best ->
        count = CounterCache.read_node_count(load_balancer_name, node)
        if count < best_count, do: {node, count}, else: best
      end)

    best_node
  end
end
