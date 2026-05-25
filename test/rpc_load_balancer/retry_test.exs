defmodule RpcLoadBalancer.RetryTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.Retry

  test "returns the function result when it never asks to retry" do
    assert :done === Retry.with_retry([retry_count: 3, retry_sleep: 1], fn -> :done end)
  end

  test "retries until the function stops returning :retry, then returns the result" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    result =
      Retry.with_retry([retry_count: 5, retry_sleep: 1], fn ->
        attempt = Agent.get_and_update(counter, fn count -> {count, count + 1} end)
        if attempt < 2, do: :retry, else: :done
      end)

    assert :done === result
    assert 3 === Agent.get(counter, & &1)
  end

  test "returns :error once a bounded retry_count is exhausted" do
    assert :error === Retry.with_retry([retry_count: 2, retry_sleep: 1], fn -> :retry end)
  end

  test "retry_count: :infinity keeps retrying without crashing and eventually returns" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    result =
      Retry.with_retry([retry_count: :infinity, retry_sleep: 1], fn ->
        attempt = Agent.get_and_update(counter, fn count -> {count, count + 1} end)
        if attempt < 3, do: :retry, else: :infinity_done
      end)

    assert :infinity_done === result
    assert 4 === Agent.get(counter, & &1)
  end

  test "retry?: false short-circuits even with retry_count: :infinity" do
    assert :error === Retry.with_retry([retry?: false, retry_count: :infinity, retry_sleep: 1], fn -> :retry end)
  end
end
