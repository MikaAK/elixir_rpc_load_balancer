defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm do
  @moduledoc """
  Behaviour for load balancer node selection.
  """

  alias RpcLoadBalancer.LoadBalancer.AlgorithmCache

  @type load_balancer_name :: atom() | module()

  @callback init(load_balancer_name(), opts :: keyword()) :: :ok
  @callback choose_from_nodes(load_balancer_name(), [node()], opts :: keyword()) :: node()
  @callback on_node_change(load_balancer_name(), {:joined | :left, [node()]}) :: :ok
  @callback release_node(load_balancer_name(), node()) :: :ok

  @optional_callbacks [init: 2, on_node_change: 2, release_node: 2]

  @spec get_algorithm(load_balancer_name()) :: ErrorMessage.t_res(nil | module())
  def get_algorithm(load_balancer_name) do
    AlgorithmCache.get(load_balancer_name)
  end

  @spec put_algorithm(load_balancer_name(), module()) :: ErrorMessage.t_ok_res()
  def put_algorithm(load_balancer_name, algorithm_module) do
    AlgorithmCache.put(load_balancer_name, algorithm_module)
  end

  @spec init(module(), load_balancer_name(), keyword()) :: :ok
  def init(algorithm, load_balancer_name, opts) do
    if function_exported?(algorithm, :init, 2) do
      algorithm.init(load_balancer_name, opts)
    else
      :ok
    end
  end

  @spec choose_from_nodes(module(), load_balancer_name(), [node()], keyword()) :: node()
  def choose_from_nodes(algorithm, load_balancer_name, node_list, opts \\ []) do
    algorithm.choose_from_nodes(load_balancer_name, node_list, opts)
  end

  @spec on_node_change(module(), load_balancer_name(), {:joined | :left, [node()]}) :: :ok
  def on_node_change(algorithm, load_balancer_name, change) do
    if function_exported?(algorithm, :on_node_change, 2) do
      algorithm.on_node_change(load_balancer_name, change)
    else
      :ok
    end
  end

  @spec release_node(module(), load_balancer_name(), node()) :: :ok
  def release_node(algorithm, load_balancer_name, node) do
    if function_exported?(algorithm, :release_node, 2) do
      algorithm.release_node(load_balancer_name, node)
    else
      :ok
    end
  end
end
