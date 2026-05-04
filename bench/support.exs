defmodule Bench.Support do
  @moduledoc """
  Shared setup for selection-algorithm benchmarks.

  Spins up the application, then starts one load balancer per algorithm.
  Algorithms are exercised via `choose_from_nodes/3` against a synthetic
  node list so we measure pure algorithm work — no `:pg` lookups, no
  network.

  Load balancer name == algorithm module (modules are atoms — zero
  allocation). Synthetic node names are a fixed compile-time pool to
  avoid dynamic atom creation.
  """

  alias RpcLoadBalancer.LoadBalancer.CounterCache
  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  @algorithms [
    {SelectionAlgorithm.Random, []},
    {SelectionAlgorithm.RoundRobin, []},
    {SelectionAlgorithm.LeastConnections, []},
    {SelectionAlgorithm.PowerOfTwo, []},
    {SelectionAlgorithm.HashRing, []},
    {SelectionAlgorithm.WeightedRoundRobin, []},
    {SelectionAlgorithm.CallDirect, []},
    {SelectionAlgorithm.LeastCpu,
     [poll_startup_jitter: 600_000, poll_interval: 600_000, cpu_sampler: &__MODULE__.fixed_cpu/0]}
  ]

  @node_pool [
    :"bench_node_1@127.0.0.1",
    :"bench_node_2@127.0.0.1",
    :"bench_node_3@127.0.0.1",
    :"bench_node_4@127.0.0.1",
    :"bench_node_5@127.0.0.1",
    :"bench_node_6@127.0.0.1",
    :"bench_node_7@127.0.0.1",
    :"bench_node_8@127.0.0.1",
    :"bench_node_9@127.0.0.1",
    :"bench_node_10@127.0.0.1",
    :"bench_node_11@127.0.0.1",
    :"bench_node_12@127.0.0.1",
    :"bench_node_13@127.0.0.1",
    :"bench_node_14@127.0.0.1",
    :"bench_node_15@127.0.0.1",
    :"bench_node_16@127.0.0.1",
    :"bench_node_17@127.0.0.1",
    :"bench_node_18@127.0.0.1",
    :"bench_node_19@127.0.0.1",
    :"bench_node_20@127.0.0.1",
    :"bench_node_21@127.0.0.1",
    :"bench_node_22@127.0.0.1",
    :"bench_node_23@127.0.0.1",
    :"bench_node_24@127.0.0.1",
    :"bench_node_25@127.0.0.1",
    :"bench_node_26@127.0.0.1",
    :"bench_node_27@127.0.0.1",
    :"bench_node_28@127.0.0.1",
    :"bench_node_29@127.0.0.1",
    :"bench_node_30@127.0.0.1",
    :"bench_node_31@127.0.0.1",
    :"bench_node_32@127.0.0.1"
  ]

  def algorithms, do: @algorithms

  def fixed_cpu, do: 50.0

  def setup do
    {:ok, _} = Application.ensure_all_started(:rpc_load_balancer)

    for {algorithm, opts} <- @algorithms do
      lb_name = lb_name_for(algorithm)
      _ = ignore_no_child(Supervisor.terminate_child(RpcLoadBalancer.Supervisor, lb_name))

      {:ok, _pid} =
        RpcLoadBalancer.start_link(
          name: lb_name,
          selection_algorithm: algorithm,
          algorithm_opts: opts
        )
    end

    :ok
  end

  def lb_name_for(algorithm), do: algorithm

  def synthetic_nodes(count) when count <= 32 do
    Enum.take(@node_pool, count)
  end

  def warm_caches(node_lists) do
    for nodes <- node_lists, node <- nodes do
      CounterCache.register_node(lb_name_for(SelectionAlgorithm.LeastConnections), node)
      CounterCache.register_node(lb_name_for(SelectionAlgorithm.PowerOfTwo), node)
      now = System.monotonic_time(:millisecond)
      NodeCpuCache.put_cpu(node, %{cpu: :rand.uniform() * 50.0, fetched_at: now})
    end

    :ok
  end

  defp ignore_no_child({:error, :not_found}), do: :ok
  defp ignore_no_child(other), do: other
end
