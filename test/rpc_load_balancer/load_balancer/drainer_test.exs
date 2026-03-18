defmodule RpcLoadBalancer.LoadBalancer.DrainerTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.Drainer
  alias RpcLoadBalancer.LoadBalancer.DrainerCache

  defp start_drainer!(name) do
    start_supervised!(DrainerCache.child_spec(name))
    Process.sleep(50)
    name
  end

  describe "track_call/1 and release_call/1" do
    test "increments and decrements in-flight count" do
      name = start_drainer!(:drainer_test_track)

      assert Drainer.in_flight_count(name) === 0

      Drainer.track_call(name)
      assert Drainer.in_flight_count(name) === 1

      Drainer.track_call(name)
      assert Drainer.in_flight_count(name) === 2

      Drainer.release_call(name)
      assert Drainer.in_flight_count(name) === 1

      Drainer.release_call(name)
      assert Drainer.in_flight_count(name) === 0
    end
  end

  describe "in_flight_count/1" do
    test "returns 0 when no calls tracked" do
      name = start_drainer!(:drainer_test_zero)
      assert Drainer.in_flight_count(name) === 0
    end
  end

  describe "drain/2" do
    test "returns :ok immediately when no in-flight calls" do
      name = start_drainer!(:drainer_test_empty)
      assert :ok === Drainer.drain(name, 100)
    end

    test "waits for in-flight calls to complete" do
      name = start_drainer!(:drainer_test_drain_wait)

      Drainer.track_call(name)

      task = Task.async(fn -> Drainer.drain(name, 5_000) end)

      Process.sleep(100)
      Drainer.release_call(name)

      assert :ok === Task.await(task)
    end

    test "returns {:error, :timeout} when calls don't complete in time" do
      name = start_drainer!(:drainer_test_timeout)

      Drainer.track_call(name)

      assert {:error, :timeout} === Drainer.drain(name, 100)

      Drainer.release_call(name)
    end

    test "counter resets to zero after successful drain" do
      name = start_drainer!(:drainer_test_cleanup)

      Drainer.track_call(name)
      assert Drainer.in_flight_count(name) === 1

      Drainer.release_call(name)
      assert :ok === Drainer.drain(name, 100)

      assert Drainer.in_flight_count(name) === 0
    end
  end
end
