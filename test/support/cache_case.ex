defmodule RpcLoadBalancer.CacheCase do
  @moduledoc """
  ExUnit case helper that registers the test pid against every
  `RpcLoadBalancer` sandboxed cache, giving each test its own
  per-PID isolated view of the cache state.

  Unlike `Cache.CaseTemplate`, this case does NOT call
  `start_supervised!` on a per-test cache supervisor — the cache
  agents are owned by the application supervisor (see
  `RpcLoadBalancer.Application`) and live for the entire VM, so
  parallel async tests cannot accidentally tear each other's agents
  down. We only need `Cache.SandboxRegistry.register_caches/1` to
  scope the test's cache reads/writes by pid.

  Use directly when a test exercises any sandboxed cache:

      defmodule RpcLoadBalancer.SomeTest do
        use ExUnit.Case, async: true
        use RpcLoadBalancer.CacheCase
      end
  """

  @sandboxed_caches [
    RpcLoadBalancer.LoadBalancer.AlgorithmCache,
    RpcLoadBalancer.LoadBalancer.HashRingCache,
    RpcLoadBalancer.LoadBalancer.IndexRegistry,
    RpcLoadBalancer.LoadBalancer.LoadBalancerOptsCache,
    RpcLoadBalancer.LoadBalancer.NodeCpuCache
  ]

  defmacro __using__(_opts) do
    sandboxed_caches = @sandboxed_caches

    quote do
      setup do
        Cache.SandboxRegistry.register_caches(unquote(sandboxed_caches))
        :ok
      end
    end
  end
end
