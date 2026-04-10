defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm do
  @moduledoc """
  Behaviour for load balancer node selection.
  """

  alias RpcLoadBalancer.LoadBalancer.AlgorithmCache

  @type load_balancer_name :: atom() | module()

  @callback init(load_balancer_name(), opts :: keyword()) :: :ok
  @callback choose_from_nodes(load_balancer_name(), [node()], opts :: keyword()) :: node()
  @callback choose_nodes(load_balancer_name(), [node()], pos_integer(), opts :: keyword()) ::
              [node()]
  @callback on_node_change(load_balancer_name(), {:joined | :left, [node()]}) :: :ok
  @callback release_node(load_balancer_name(), node()) :: :ok
  @callback local?() :: boolean()
  @callback child_specs(load_balancer_name(), opts :: keyword()) :: [Supervisor.child_spec()]
  @callback caches() :: [module()]

  @optional_callbacks [
    init: 2,
    choose_nodes: 4,
    on_node_change: 2,
    release_node: 2,
    local?: 0,
    child_specs: 2,
    caches: 0
  ]
  @optional_callbacks [init: 2, choose_nodes: 4, on_node_change: 2, release_node: 2, local?: 0, child_specs: 2]

  @spec get_algorithm(load_balancer_name()) :: {:ok, module() | nil} | {:error, ErrorMessage.t()}
  def get_algorithm(load_balancer_name) do
    AlgorithmCache.get_algorithm(load_balancer_name)
  end

  @spec put_algorithm(load_balancer_name(), module()) :: :ok | {:error, ErrorMessage.t()}
  def put_algorithm(load_balancer_name, algorithm_module) do
    AlgorithmCache.put_algorithm(load_balancer_name, algorithm_module)
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

  @spec choose_nodes(module(), load_balancer_name(), [node()], pos_integer(), keyword()) ::
          [node()]
  def choose_nodes(algorithm, load_balancer_name, node_list, count, opts \\ []) do
    if function_exported?(algorithm, :choose_nodes, 4) do
      algorithm.choose_nodes(load_balancer_name, node_list, count, opts)
    else
      node_list
      |> Enum.shuffle()
      |> Enum.take(count)
    end
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

  @spec local?(module()) :: boolean()
  def local?(algorithm) do
    function_exported?(algorithm, :local?, 0) and algorithm.local?()
  end

  @spec child_specs(module(), load_balancer_name(), keyword()) :: [Supervisor.child_spec()]
  def child_specs(algorithm, load_balancer_name, opts) do
    # Force-load the algorithm module so function_exported?/3 sees optional
    # callbacks; ignore the result — only the side effect matters here.
    _ = Code.ensure_loaded(algorithm)

    if function_exported?(algorithm, :child_specs, 2) do
      algorithm.child_specs(load_balancer_name, opts)
    else
      []
    end
  end

  @doc """
  Returns the cache modules an algorithm needs.

  Algorithms that don't require any caches can omit the `caches/0`
  callback entirely; we treat that as `[]`.
  """
  @spec caches(module()) :: [module()]
  def caches(algorithm) do
    _ = Code.ensure_loaded(algorithm)

    if function_exported?(algorithm, :caches, 0) do
      algorithm.caches()
    else
      []
    end
  end

  @doc """
  Returns the union of caches required by every algorithm passed in.

  Used by `RpcLoadBalancer.Application` to start exactly the cache
  agents the configured algorithms need — no more, no less.
  """
  @spec all_caches([module()]) :: [module()]
  def all_caches(algorithms) do
    algorithms
    |> Enum.flat_map(&caches/1)
    |> Enum.uniq()
  end
end
