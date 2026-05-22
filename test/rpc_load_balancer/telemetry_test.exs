defmodule RpcLoadBalancer.TelemetryTest do
  @moduledoc """
  Verify `RpcLoadBalancer.call/5` and `RpcLoadBalancer.cast/5` emit
  `:telemetry.span/3` events under the documented event prefix.
  """

  use ExUnit.Case, async: true

  @event_prefix [:rpc_load_balancer, :rpc]

  setup do
    handler_id = "rpc-lb-telemetry-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          @event_prefix ++ [:start],
          @event_prefix ++ [:stop],
          @event_prefix ++ [:exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  describe "call/5" do
    test "emits :start and :stop spans with type: :call metadata" do
      assert {:ok, :pong} =
               RpcLoadBalancer.call(node(), Kernel, :apply, [fn -> :pong end, []])

      assert_receive {:telemetry, [:rpc_load_balancer, :rpc, :start], _measurements, start_meta}
      assert start_meta.type === :call
      assert start_meta.node === node()
      assert start_meta.module === "Kernel"
      assert start_meta.function === :apply

      assert_receive {:telemetry, [:rpc_load_balancer, :rpc, :stop], measurements, stop_meta}
      assert is_integer(measurements.duration)
      assert stop_meta.status === :ok
      assert stop_meta.type === :call
    end

    test "stop metadata includes :load_balancer name when configured" do
      {:ok, _pid} = RpcLoadBalancer.start_link(name: :test_telemetry_lb)

      RpcLoadBalancer.call(node(), Kernel, :apply, [fn -> :ok end, []],
        load_balancer: :test_telemetry_lb
      )

      assert_receive {:telemetry, [:rpc_load_balancer, :rpc, :stop], _measurements, meta}
      assert meta.load_balancer === :test_telemetry_lb
    end

    test "load_balancer is nil when not configured" do
      RpcLoadBalancer.call(node(), Kernel, :apply, [fn -> :ok end, []])

      assert_receive {:telemetry, [:rpc_load_balancer, :rpc, :start], _measurements, meta}
      assert is_nil(meta.load_balancer)
    end

    test "status is not :ok when the call returns an error tuple" do
      RpcLoadBalancer.call(:"nonexistent@nowhere", Kernel, :apply, [fn -> :nope end, []],
        timeout: 50
      )

      assert_receive {:telemetry, [:rpc_load_balancer, :rpc, :stop], _measurements, meta}
      assert meta.status !== :ok
    end
  end

  describe "cast/5" do
    test "emits :start and :stop spans with type: :cast metadata" do
      assert :ok = RpcLoadBalancer.cast(node(), Kernel, :apply, [fn -> :ok end, []])

      assert_receive {:telemetry, [:rpc_load_balancer, :rpc, :start], _measurements, start_meta}
      assert start_meta.type === :cast

      assert_receive {:telemetry, [:rpc_load_balancer, :rpc, :stop], _measurements, stop_meta}
      assert stop_meta.type === :cast
    end
  end
end
