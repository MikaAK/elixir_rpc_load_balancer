defmodule RpcLoadBalancer.LoadBalancer.Pg do
  @moduledoc """
  Wrapper around `:pg` used by `RpcLoadBalancer.LoadBalancer`.

  Encapsulates the shared `:pg` group name and the patterns for reading
  membership and fanning out RPC calls to remote members.
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

  @doc """
  Returns remote node names (non-local, deduplicated) registered for
  the given load balancer.
  """
  @spec remote_members(atom() | module()) :: [node()]
  def remote_members(load_balancer_name) do
    @pg_group_name
    |> :pg.get_members(load_balancer_name)
    |> Enum.map(&node/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 === node()))
  end

  @doc """
  Runs `:erpc.multicall/5` against every remote member of the group
  and returns `[{remote_node, result}]` pairs in membership order.

  Empty-membership shortcut: returns `[]` without invoking `:erpc`.
  """
  @spec multicall(atom() | module(), module(), atom(), [any()], timeout()) ::
          [{node(), any()}]
  def multicall(load_balancer_name, module, fun, args, timeout) do
    case remote_members(load_balancer_name) do
      [] ->
        []

      remotes ->
        remotes
        |> :erpc.multicall(module, fun, args, timeout)
        |> then(&Enum.zip(remotes, &1))
    end
  end
end
