defmodule RpcLoadBalancer.LoadBalancer.DrainerTest do
  use ExUnit.Case

  alias RpcLoadBalancer.LoadBalancer.Drainer
  alias RpcLoadBalancer.LoadBalancer.DrainerCache
  alias RpcLoadBalancer.LoadBalancer.IndexRegistry

  defp start_drainer!(name) do
    start_supervised!({Cache, [IndexRegistry, DrainerCache]})
    Process.sleep(50)
    IndexRegistry.init_counter(:rpc_lb_drainer_cache)
    Drainer.register(name)
  end

  describe "track_call/1 and release_call/1" do
    test "increments and decrements in-flight count" do
      index = start_drainer!(:drainer_test_track)

      assert Drainer.in_flight_count(index) === 0

      Drainer.track_call(index)
      assert Drainer.in_flight_count(index) === 1

      Drainer.track_call(index)
      assert Drainer.in_flight_count(index) === 2

      Drainer.release_call(index)
      assert Drainer.in_flight_count(index) === 1

      Drainer.release_call(index)
      assert Drainer.in_flight_count(index) === 0
    end
  end

  describe "in_flight_count/1" do
    test "returns 0 when no calls tracked" do
      index = start_drainer!(:drainer_test_zero)
      assert Drainer.in_flight_count(index) === 0
    end
  end

  describe "drain/2" do
    test "returns :ok immediately when no in-flight calls" do
      index = start_drainer!(:drainer_test_empty)
      assert :ok === Drainer.drain(index, 100)
    end

    test "waits for in-flight calls to complete" do
      index = start_drainer!(:drainer_test_drain_wait)

      Drainer.track_call(index)

      task = Task.async(fn -> Drainer.drain(index, 5_000) end)

      Process.sleep(100)
      Drainer.release_call(index)

      assert :ok === Task.await(task)
    end

    test "returns {:error, :timeout} when calls don't complete in time" do
      index = start_drainer!(:drainer_test_timeout)

      Drainer.track_call(index)

      assert {:error, :timeout} === Drainer.drain(index, 100)

      Drainer.release_call(index)
    end

    test "counter resets to zero after successful drain" do
      index = start_drainer!(:drainer_test_cleanup)

      Drainer.track_call(index)
      assert Drainer.in_flight_count(index) === 1

      Drainer.release_call(index)
      assert :ok === Drainer.drain(index, 100)

      assert Drainer.in_flight_count(index) === 0
    end
  end
end
