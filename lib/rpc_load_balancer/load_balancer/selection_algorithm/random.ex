defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.Random do
  @moduledoc """
  Random node selection algorithm.
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  @impl true
  def choose_from_nodes(_load_balancer_name, node_list, _opts \\ []) do
    Enum.random(node_list)
  end
end
