defmodule RpcLoadBalancer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RpcLoadBalancer.LoadBalancer.Pg,
      {Cache,
       [
         RpcLoadBalancer.LoadBalancer.AlgorithmCache,
         RpcLoadBalancer.LoadBalancer.CounterCache
       ]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RpcLoadBalancer.Supervisor)
  end
end
