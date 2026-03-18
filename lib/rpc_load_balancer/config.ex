defmodule RpcLoadBalancer.Config do
  @moduledoc """
  Configuration defaults for `RpcLoadBalancer`.

  All values can be overridden via `Application.put_env/3`:

      config :rpc_load_balancer,
        call_directly?: false,
        retry?: true,
        retry_count: 5
  """

  @app :rpc_load_balancer

  @spec call_directly?() :: boolean()
  def call_directly? do
    Application.get_env(@app, :call_directly?, false)
  end

  @spec retry?() :: boolean()
  def retry? do
    Application.get_env(@app, :retry?, true)
  end

  @spec retry_count() :: non_neg_integer()
  def retry_count do
    Application.get_env(@app, :retry_count, 5)
  end
end
