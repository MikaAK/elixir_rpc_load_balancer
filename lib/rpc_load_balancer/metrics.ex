defmodule RpcLoadBalancer.Metrics do
  @moduledoc """
  `Telemetry.Metrics` definitions for `RpcLoadBalancer.call/5`,
  `RpcLoadBalancer.cast/5`, and node-selection events.

  Consumers register these in their telemetry supervisor — e.g. through
  `PrometheusTelemetry` — to expose `rpc_load_balancer.*` series.

      # in your_app/application.ex
      children = [
        {PrometheusTelemetry,
         exporter: [enabled?: prod?()],
         metrics: [
           RpcLoadBalancer.Metrics.metrics(),
           PrometheusTelemetry.Metrics.VM.metrics()
         ]}
      ]

  ## Emitted events

    * `[:rpc_load_balancer, :rpc, :start]`
    * `[:rpc_load_balancer, :rpc, :stop]` — measurement `:duration` (`:native`)
    * `[:rpc_load_balancer, :rpc, :exception]`
    * `[:rpc_load_balancer, :node_selected]` — `count: 1, members_count: pool_size`
    * `[:rpc_load_balancer, :node_selected, :empty]` — `count: 1`

  ## Metadata

  RPC events:

    * `:type` — `:call` or `:cast`
    * `:node` — target node atom
    * `:module` — `inspect/1`'d module name (string, low-cardinality)
    * `:function` — function name atom
    * `:load_balancer` — load balancer name atom, or `nil` for direct calls
    * `:status` (stop only) — `:ok | :error | atom()` mapped from `ErrorMessage` code

  Selection events:

    * `:algorithm` — full algorithm module atom (e.g. `Random`, `RoundRobin`)
    * `:load_balancer` — load balancer name atom
    * `:node` — selected node atom (omitted on `:empty` event)

  ## Prometheus series

    * `rpc_load_balancer.rpc.request.start.count`
    * `rpc_load_balancer.rpc.request.stop.count`
    * `rpc_load_balancer.rpc.duration.milliseconds`
    * `rpc_load_balancer.node.selected.count`
    * `rpc_load_balancer.node.selected.empty.count`
    * `rpc_load_balancer.node.pool_size`
  """

  import Telemetry.Metrics, only: [counter: 2, distribution: 2]

  @rpc_event_prefix [:rpc_load_balancer, :rpc]
  @selected_event [:rpc_load_balancer, :node_selected]
  @empty_event [:rpc_load_balancer, :node_selected, :empty]

  @duration_buckets [
    0.1,
    0.5,
    1,
    2.5,
    5,
    10,
    25,
    50,
    100,
    250,
    500,
    1_000,
    2_500,
    5_000,
    10_000,
    30_000,
    60_000
  ]

  @pool_buckets [1, 2, 3, 5, 10, 20, 50, 100, 250]

  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      counter(
        "rpc_load_balancer.rpc.request.start.count",
        event_name: @rpc_event_prefix ++ [:start],
        measurement: :count,
        description: "RPC requests started",
        tags: [:node, :module, :function, :type, :load_balancer]
      ),
      counter(
        "rpc_load_balancer.rpc.request.stop.count",
        event_name: @rpc_event_prefix ++ [:stop],
        measurement: :count,
        description: "RPC requests completed",
        tags: [:node, :module, :function, :type, :load_balancer, :status]
      ),
      distribution(
        "rpc_load_balancer.rpc.duration.milliseconds",
        event_name: @rpc_event_prefix ++ [:stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        description: "RPC request duration in milliseconds",
        tags: [:node, :module, :function, :type, :load_balancer, :status],
        reporter_options: [buckets: @duration_buckets]
      ),
      counter(
        "rpc_load_balancer.node.selected.count",
        event_name: @selected_event,
        measurement: :count,
        description: "Node selections per algorithm + load balancer + target node",
        tags: [:algorithm, :load_balancer, :node]
      ),
      counter(
        "rpc_load_balancer.node.selected.empty.count",
        event_name: @empty_event,
        measurement: :count,
        description: "Selection attempts with zero members (no node could be chosen)",
        tags: [:algorithm, :load_balancer]
      ),
      distribution(
        "rpc_load_balancer.node.pool_size",
        event_name: @selected_event,
        measurement: :members_count,
        description: "Pool size observed at selection time per algorithm + load balancer",
        tags: [:algorithm, :load_balancer],
        reporter_options: [buckets: @pool_buckets]
      )
    ]
  end
end
