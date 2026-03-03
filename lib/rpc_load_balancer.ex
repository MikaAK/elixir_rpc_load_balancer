defmodule RpcLoadBalancer do
  @moduledoc """
  Executes Remote Procedure Calls.

  This library provides:

  - RPC wrappers around `:erpc.call/5` and `:erpc.cast/4`
  - A distributed node load balancer built on `:pg`
  """

  @spec call(node(), module(), atom(), [any()], timeout: timeout()) :: ErrorMessage.t_res(any())
  def call(node, module, fun, args, opts \\ [timeout: :timer.seconds(10)]) do
    timeout = Keyword.get(opts, :timeout, :timer.seconds(10))

    try do
      {:ok, :erpc.call(node, module, fun, args, timeout)}
    rescue
      e in ErlangError ->
        {:error, erlang_error_to_error_message(e, node)}

      e ->
        {:error, ErrorMessage.service_unavailable("unavailable", %{node: node, details: e})}
    end
  end

  @spec cast(node(), module(), atom(), [term()]) :: :ok | {:error, ErrorMessage.t()}
  def cast(node, module, fun, args) do
    :erpc.cast(node, module, fun, args)
  rescue
    e in ErlangError ->
      {:error, erlang_error_to_error_message(e, node)}

    e ->
      {:error, ErrorMessage.service_unavailable("unavailable", %{node: node, details: e})}
  end

  defp erlang_error_to_error_message(%ErlangError{original: {:erpc, :timeout}}, node) do
    ErrorMessage.request_timeout("timeout", %{node: node})
  end

  defp erlang_error_to_error_message(%ErlangError{original: {:erpc, :noconnection}}, node) do
    ErrorMessage.service_unavailable("noconnection", %{node: node})
  end

  defp erlang_error_to_error_message(%ErlangError{original: {:erpc, :badarg}}, node) do
    ErrorMessage.bad_request("bad request", %{node: node})
  end

  defp erlang_error_to_error_message(%ErlangError{} = error, _node) do
    ErrorMessage.service_unavailable("unavailable", %{details: error})
  end
end
