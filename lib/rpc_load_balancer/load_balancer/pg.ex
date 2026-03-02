defmodule RpcLoadBalancer.LoadBalancer.Pg do
  @moduledoc """
  Wrapper around `:pg` used by `RpcLoadBalancer.LoadBalancer`.
  """

  @pg_group_name :rpc_load_balancer

  @spec start_link(any()) :: {:ok, pid()} | {:error, any()}
  def start_link(_opts \\ []) do
    :pg.start_link(@pg_group_name)
  end

  @spec child_spec(any()) :: map()
  def child_spec(opts) do
    %{
      id: @pg_group_name,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec pg_group_name() :: atom()
  def pg_group_name, do: @pg_group_name
end
