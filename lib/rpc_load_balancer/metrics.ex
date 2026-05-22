defmodule RpcLoadBalancer.Metrics do
  @moduledoc """
  `Telemetry.Metrics` definitions for `RpcLoadBalancer.call/5` and
  `RpcLoadBalancer.cast/5` spans.

  Consumers register these in their telemetry supervisor — e.g. through
  `PrometheusTelemetry` — to expose `rpc_load_balancer.rpc.*` series.

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

  ## Metadata

    * `:type` — `:call` or `:cast`
    * `:node` — target node atom
    * `:module` — `inspect/1`'d module name (string, low-cardinality)
    * `:function` — function name atom
    * `:load_balancer` — load balancer name atom, or `nil` for direct calls
    * `:status` (stop only) — `:ok | :error | atom()` mapped from `ErrorMessage` code

  ## Prometheus series

    * `rpc_load_balancer.rpc.request.start.count`
    * `rpc_load_balancer.rpc.request.stop.count`
    * `rpc_load_balancer.rpc.duration.milliseconds`
  """

  import Telemetry.Metrics, only: [counter: 2, distribution: 2]

  @event_prefix [:rpc_load_balancer, :rpc]

  @buckets [1, 5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]

  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      counter(
        "rpc_load_balancer.rpc.request.start.count",
        event_name: @event_prefix ++ [:start],
        measurement: :count,
        description: "RPC requests started",
        tags: [:node, :module, :function, :type, :load_balancer]
      ),
      counter(
        "rpc_load_balancer.rpc.request.stop.count",
        event_name: @event_prefix ++ [:stop],
        measurement: :count,
        description: "RPC requests completed",
        tags: [:node, :module, :function, :type, :load_balancer, :status]
      ),
      distribution(
        "rpc_load_balancer.rpc.duration.milliseconds",
        event_name: @event_prefix ++ [:stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        description: "RPC request duration in milliseconds",
        tags: [:node, :module, :function, :type, :load_balancer, :status],
        reporter_options: [buckets: @buckets]
      )
    ]
  end
end
