defmodule RpcLoadBalancer.LoadBalancer.AlgorithmCache do
  use Cache,
    adapter: Cache.PersistentTerm,
    name: :rpc_lb_algorithm_cache,
    sandbox?: false,
    opts: []

  @spec get_algorithm(atom()) :: {:ok, module() | nil} | {:error, ErrorMessage.t()}
  def get_algorithm(load_balancer_name) do
    get(load_balancer_name)
  end

  @spec put_algorithm(atom(), module()) :: :ok
  def put_algorithm(load_balancer_name, algorithm) do
    put(load_balancer_name, nil, algorithm)
  end
end
