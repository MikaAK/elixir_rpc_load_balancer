Code.require_file("support.exs", __DIR__)

alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

:ok = Bench.Support.setup()

nodes = Bench.Support.synthetic_nodes(8)
:ok = Bench.Support.warm_caches([nodes])

algorithms = Bench.Support.algorithms()

scenarios =
  Map.new(algorithms, fn {algorithm, _opts} ->
    label = algorithm |> Module.split() |> List.last()
    lb_name = Bench.Support.lb_name_for(algorithm)
    key_counter = :counters.new(1, [:atomics])

    fun =
      if algorithm === SelectionAlgorithm.HashRing do
        fn ->
          :ok = :counters.add(key_counter, 1, 1)
          i = :counters.get(key_counter, 1)
          algorithm.choose_from_nodes(lb_name, nodes, key: "key:#{rem(i, 1024)}")
        end
      else
        fn -> algorithm.choose_from_nodes(lb_name, nodes, []) end
      end

    {label, fun}
  end)

Benchee.run(
  scenarios,
  parallel: 32,
  warmup: 1,
  time: 3,
  memory_time: 0,
  reduction_time: 0,
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}]
)
