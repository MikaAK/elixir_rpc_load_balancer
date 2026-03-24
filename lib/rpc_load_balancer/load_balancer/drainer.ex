defmodule RpcLoadBalancer.LoadBalancer.Drainer do
  @moduledoc """
  Tracks in-flight RPC calls and provides graceful connection draining.

  Uses `DrainerCache` (backed by `Cache.Counter`) to atomically track
  the number of in-flight calls. During shutdown, the server leaves its
  `:pg` group and calls `drain/2` to wait for existing calls to complete
  before the process terminates.
  """

  alias RpcLoadBalancer.LoadBalancer.DrainerCache

  @default_drain_timeout :timer.seconds(15)
  @poll_interval_ms 50

  @spec register(atom()) :: non_neg_integer()
  def register(load_balancer_name) do
    DrainerCache.register(load_balancer_name)
  end

  @spec track_call(non_neg_integer()) :: :ok
  def track_call(drainer_index) do
    DrainerCache.increment(drainer_index)
  end

  @spec release_call(non_neg_integer()) :: :ok
  def release_call(drainer_index) do
    DrainerCache.decrement(drainer_index)
  end

  @spec in_flight_count(non_neg_integer()) :: non_neg_integer()
  def in_flight_count(drainer_index) do
    DrainerCache.count(drainer_index)
  end

  @spec drain(non_neg_integer(), timeout()) :: :ok | {:error, :timeout}
  def drain(drainer_index, timeout \\ @default_drain_timeout) do
    deadline = compute_deadline(timeout)
    await_drain(drainer_index, deadline)
  end

  defp compute_deadline(:infinity), do: :infinity
  defp compute_deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp await_drain(drainer_index, deadline) do
    if in_flight_count(drainer_index) <= 0 do
      :ok
    else
      if deadline !== :infinity and System.monotonic_time(:millisecond) >= deadline do
        {:error, :timeout}
      else
        Process.sleep(@poll_interval_ms)
        await_drain(drainer_index, deadline)
      end
    end
  end
end
