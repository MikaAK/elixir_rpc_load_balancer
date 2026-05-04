Code.require_file("support.exs", __DIR__)

alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

:ok = Bench.Support.setup()

node_counts = [2, 8, 32]
node_lists = Map.new(node_counts, &{&1, Bench.Support.synthetic_nodes(&1)})

:ok = Bench.Support.warm_caches(Map.values(node_lists))

inputs =
  Map.new(node_counts, fn count ->
    {"#{count} nodes", node_lists[count]}
  end)

algorithms = Bench.Support.algorithms()

scenarios =
  Map.new(algorithms, fn {algorithm, _opts} ->
    label = algorithm |> Module.split() |> List.last()
    lb_name = Bench.Support.lb_name_for(algorithm)
    key_counter = :counters.new(1, [:atomics])

    fun =
      if algorithm === SelectionAlgorithm.HashRing do
        fn nodes ->
          :ok = :counters.add(key_counter, 1, 1)
          i = :counters.get(key_counter, 1)
          algorithm.choose_from_nodes(lb_name, nodes, key: "key:#{rem(i, 1024)}")
        end
      else
        fn nodes -> algorithm.choose_from_nodes(lb_name, nodes, []) end
      end

    {label, fun}
  end)

Benchee.run(
  scenarios,
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  reduction_time: 1,
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}]
)
