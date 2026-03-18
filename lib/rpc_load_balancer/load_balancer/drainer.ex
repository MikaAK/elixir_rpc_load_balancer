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

  @spec track_call(atom()) :: :ok
  def track_call(load_balancer_name) do
    DrainerCache.increment(load_balancer_name)
  end

  @spec release_call(atom()) :: :ok
  def release_call(load_balancer_name) do
    DrainerCache.decrement(load_balancer_name)
  end

  @spec in_flight_count(atom()) :: non_neg_integer()
  def in_flight_count(load_balancer_name) do
    DrainerCache.count(load_balancer_name)
  end

  @spec drain(atom(), timeout()) :: :ok | {:error, :timeout}
  def drain(load_balancer_name, timeout \\ @default_drain_timeout) do
    deadline = compute_deadline(timeout)
    await_drain(load_balancer_name, deadline)
  end

  defp compute_deadline(:infinity), do: :infinity
  defp compute_deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp await_drain(load_balancer_name, deadline) do
    if in_flight_count(load_balancer_name) <= 0 do
      :ok
    else
      if deadline !== :infinity and System.monotonic_time(:millisecond) >= deadline do
        {:error, :timeout}
      else
        Process.sleep(@poll_interval_ms)
        await_drain(load_balancer_name, deadline)
      end
    end
  end
end
