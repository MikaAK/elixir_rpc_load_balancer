defmodule RpcLoadBalancer.MetricsTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.Metrics

  describe "metrics/0" do
    test "returns six Telemetry.Metrics definitions" do
      assert length(Metrics.metrics()) === 6
    end

    test "start counter listens to [:rpc_load_balancer, :rpc, :start]" do
      [start_counter | _] =
        Enum.filter(
          Metrics.metrics(),
          &(&1.name === [:rpc_load_balancer, :rpc, :request, :start, :count])
        )

      assert start_counter.event_name === [:rpc_load_balancer, :rpc, :start]
    end

    test "stop counter listens to [:rpc_load_balancer, :rpc, :stop]" do
      [stop_counter | _] =
        Enum.filter(
          Metrics.metrics(),
          &(&1.name === [:rpc_load_balancer, :rpc, :request, :stop, :count])
        )

      assert stop_counter.event_name === [:rpc_load_balancer, :rpc, :stop]
    end

    test "duration distribution uses millisecond unit and listens to :stop" do
      [duration | _] =
        Enum.filter(
          Metrics.metrics(),
          &(&1.name === [:rpc_load_balancer, :rpc, :duration, :milliseconds])
        )

      assert duration.event_name === [:rpc_load_balancer, :rpc, :stop]
      assert duration.unit === :millisecond
    end

    test "stop counter tags include :status" do
      [stop_counter | _] =
        Enum.filter(
          Metrics.metrics(),
          &(&1.name === [:rpc_load_balancer, :rpc, :request, :stop, :count])
        )

      assert :status in stop_counter.tags
      assert :load_balancer in stop_counter.tags
    end

    test "start counter does NOT tag :status (not in :start metadata)" do
      [start_counter | _] =
        Enum.filter(
          Metrics.metrics(),
          &(&1.name === [:rpc_load_balancer, :rpc, :request, :start, :count])
        )

      refute :status in start_counter.tags
    end

    test "node.selected.count listens to [:rpc_load_balancer, :node_selected]" do
      [selected | _] =
        Enum.filter(
          Metrics.metrics(),
          &(&1.name === [:rpc_load_balancer, :node, :selected, :count])
        )

      assert selected.event_name === [:rpc_load_balancer, :node_selected]
      assert :algorithm in selected.tags
      assert :load_balancer in selected.tags
      assert :node in selected.tags
    end

    test "node.selected.empty.count listens to [:rpc_load_balancer, :node_selected, :empty]" do
      [empty | _] =
        Enum.filter(
          Metrics.metrics(),
          &(&1.name === [:rpc_load_balancer, :node, :selected, :empty, :count])
        )

      assert empty.event_name === [:rpc_load_balancer, :node_selected, :empty]
      assert :algorithm in empty.tags
      assert :load_balancer in empty.tags
      refute :node in empty.tags
    end

    test "node.pool_size distribution measures :members_count from :node_selected" do
      [pool | _] =
        Enum.filter(
          Metrics.metrics(),
          &(&1.name === [:rpc_load_balancer, :node, :pool_size])
        )

      assert pool.event_name === [:rpc_load_balancer, :node_selected]
      assert pool.measurement === :members_count
    end
  end
end
