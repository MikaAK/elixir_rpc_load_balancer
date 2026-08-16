defmodule RpcLoadBalancer.Config do
  @moduledoc """
  Configuration defaults for `RpcLoadBalancer`.

  All values are read from the `:rpc_load_balancer` application env:

      config :rpc_load_balancer,
        call_directly?: false,
        retry?: true,
        retry_count: 5,
        excluded_node_patterns: []

    * `:call_directly?` — run load-balanced and random-node calls locally via
      `apply/3` / `spawn/3` (default `false`)
    * `:retry?` — retry when no node is available (default `true`)
    * `:retry_count` — retries after the first attempt (default `5`)
    * `:excluded_node_patterns` — see `RpcLoadBalancer.NodeFilter` (default `[]`)
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

  @spec excluded_node_patterns() :: [String.t()]
  def excluded_node_patterns do
    Application.get_env(@app, :excluded_node_patterns, [])
  end
end
