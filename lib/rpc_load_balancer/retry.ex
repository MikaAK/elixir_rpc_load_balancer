defmodule RpcLoadBalancer.Retry do
  @moduledoc """
  Retry logic for RPC operations that may fail when no nodes are available.
  """

  @default_sleep :timer.seconds(5)

  @spec with_retry(keyword(), (-> result)) :: result when result: any()
  def with_retry(opts \\ [], fun) do
    retry? = Keyword.get(opts, :retry?, RpcLoadBalancer.Config.retry?())
    retry_count = Keyword.get(opts, :retry_count, RpcLoadBalancer.Config.retry_count())
    sleep = Keyword.get(opts, :retry_sleep, @default_sleep)

    retry_loop(fun, retry?, retry_count, sleep)
  end

  defp retry_loop(fun, retry?, retry_count, sleep) do
    case fun.() do
      :retry when retry? and retry_count > 0 ->
        Process.sleep(sleep)
        retry_loop(fun, retry?, retry_count - 1, sleep)

      :retry ->
        :error

      result ->
        result
    end
  end
end
