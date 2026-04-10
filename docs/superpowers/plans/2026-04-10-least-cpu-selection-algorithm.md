# Least CPU Selection Algorithm — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `LeastCpu` selection algorithm that routes RPC calls to the node with the lowest CPU utilization, using a background poller with local caching and inline refresh for stale entries.

**Architecture:** The `SelectionAlgorithm` behaviour gains a new optional `child_specs/2` callback. `RpcLoadBalancer.init/1` checks for it and injects those children into the supervisor tree. `LeastCpu` uses this to start a `Poller` GenServer that samples local CPU and fetches remote CPU via `:erpc`, storing everything in a new `NodeCpuCache` (ETS-backed via `elixir_cache`). Selection reads from cache, refreshes inline if stale, and randomly picks from nodes within a configurable threshold of the minimum.

**Tech Stack:** Elixir, `elixir_cache` (ETS adapter), `:erpc`, `:scheduler.utilization/1`, `:cpu_sup`

**Spec:** `docs/superpowers/specs/2026-04-10-least-cpu-selection-algorithm-design.md`

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `lib/rpc_load_balancer/load_balancer/node_cpu_cache.ex` | ETS cache for local+remote CPU metrics |
| Create | `lib/rpc_load_balancer/load_balancer/selection_algorithm/least_cpu.ex` | LeastCpu algorithm behaviour impl |
| Create | `lib/rpc_load_balancer/load_balancer/selection_algorithm/least_cpu/poller.ex` | GenServer: samples local CPU, polls remote nodes |
| Modify | `lib/rpc_load_balancer/load_balancer/selection_algorithm.ex` | Add `child_specs/2` optional callback + dispatch |
| Modify | `lib/rpc_load_balancer.ex:39-51` | Inject algorithm child specs + NodeCpuCache into supervisor |
| Create | `test/rpc_load_balancer/selection_algorithm/least_cpu_test.exs` | Algorithm selection tests |
| Create | `test/rpc_load_balancer/selection_algorithm/least_cpu/poller_test.exs` | Poller GenServer tests |
| Modify | `test/rpc_load_balancer/load_balancer_test.exs` | Test child_specs supervisor integration |

---

### Task 1: Add `child_specs/2` to SelectionAlgorithm Behaviour

**Files:**
- Modify: `lib/rpc_load_balancer/load_balancer/selection_algorithm.ex:17-18` (optional_callbacks) and add dispatch function

- [ ] **Step 1: Add the callback and optional_callbacks entry**

In `lib/rpc_load_balancer/load_balancer/selection_algorithm.ex`, add the callback after the existing `@callback local?()` line (line 16):

```elixir
@callback child_specs(load_balancer_name(), opts :: keyword()) :: [Supervisor.child_spec()]
```

Update the `@optional_callbacks` list on line 18 to include `child_specs: 2`:

```elixir
@optional_callbacks [init: 2, choose_nodes: 4, on_node_change: 2, release_node: 2, local?: 0, child_specs: 2]
```

- [ ] **Step 2: Add the dispatch function**

Add this function after the `local?/1` function (after line 77):

```elixir
@spec child_specs(module(), load_balancer_name(), keyword()) :: [Supervisor.child_spec()]
def child_specs(algorithm, load_balancer_name, opts) do
  if function_exported?(algorithm, :child_specs, 2) do
    algorithm.child_specs(load_balancer_name, opts)
  else
    []
  end
end
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles with no warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/rpc_load_balancer/load_balancer/selection_algorithm.ex
git commit -m "add: child_specs/2 optional callback to SelectionAlgorithm behaviour"
```

---

### Task 2: Inject Algorithm Children into Supervisor

**Files:**
- Modify: `lib/rpc_load_balancer.ex:39-51` (the `init/1` function)

- [ ] **Step 1: Modify `RpcLoadBalancer.init/1` to extract algorithm and build child specs**

Replace the `init/1` function in `lib/rpc_load_balancer.ex` (lines 39-51) with:

```elixir
@impl true
def init(opts) do
  algorithm = Keyword.get(opts, :selection_algorithm, SelectionAlgorithm.Random)
  algorithm_opts = Keyword.get(opts, :algorithm_opts, [])
  name = Keyword.fetch!(opts, :name)

  algorithm_children = SelectionAlgorithm.child_specs(algorithm, name, algorithm_opts)

  children =
    [
      {Cache,
       [
         RpcLoadBalancer.LoadBalancer.IndexRegistry,
         RpcLoadBalancer.LoadBalancer.AlgorithmCache,
         RpcLoadBalancer.LoadBalancer.ValueCache,
         RpcLoadBalancer.LoadBalancer.DrainerCache,
         RpcLoadBalancer.LoadBalancer.CounterCache
       ]}
    ] ++ algorithm_children ++ [
      {RpcLoadBalancer.LoadBalancer, opts}
    ]

  Supervisor.init(children, strategy: :one_for_all)
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles with no warnings.

- [ ] **Step 3: Run existing tests to confirm no regressions**

Run: `mix test`
Expected: All existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/rpc_load_balancer.ex
git commit -m "add: inject algorithm child_specs into supervisor tree"
```

---

### Task 3: Create NodeCpuCache

**Files:**
- Create: `lib/rpc_load_balancer/load_balancer/node_cpu_cache.ex`

- [ ] **Step 1: Create the cache module**

Create `lib/rpc_load_balancer/load_balancer/node_cpu_cache.ex`:

```elixir
defmodule RpcLoadBalancer.LoadBalancer.NodeCpuCache do
  @moduledoc """
  ETS-backed cache for CPU metrics keyed by `{load_balancer_name, node}`.

  Stores `%{cpu: float(), fetched_at: integer()}` for both local and remote
  nodes. Written by `LeastCpu.Poller` and read by the `LeastCpu` algorithm
  during node selection.
  """

  use Cache,
    adapter: Cache.ETS,
    name: :rpc_lb_node_cpu_cache,
    sandbox?: false,
    opts: []
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles with no warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/rpc_load_balancer/load_balancer/node_cpu_cache.ex
git commit -m "add: NodeCpuCache ETS cache for CPU metrics"
```

---

### Task 4: Create LeastCpu.Poller GenServer

**Files:**
- Create: `lib/rpc_load_balancer/load_balancer/selection_algorithm/least_cpu/poller.ex`
- Create: `test/rpc_load_balancer/selection_algorithm/least_cpu/poller_test.exs`

- [ ] **Step 1: Write the failing test for local CPU sampling**

Create `test/rpc_load_balancer/selection_algorithm/least_cpu/poller_test.exs`:

```elixir
defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.PollerTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller

  defp start_poller!(name, opts \\ []) do
    default_opts = [
      load_balancer_name: name,
      poll_interval: 100,
      metric_source: :scheduler_utilization
    ]

    cache_children = [
      {Cache, [NodeCpuCache]}
    ]

    start_supervised!(%{
      id: :"#{name}_caches",
      start: {Supervisor, :start_link, [cache_children, [strategy: :one_for_one]]},
      type: :supervisor
    })

    start_supervised!({Poller, Keyword.merge(default_opts, opts)})
    Process.sleep(150)
    name
  end

  test "writes local CPU metric to NodeCpuCache" do
    name = start_poller!(:poller_local)

    assert {:ok, %{cpu: cpu, fetched_at: fetched_at}} =
             NodeCpuCache.get({name, node()})

    assert is_float(cpu)
    assert cpu >= 0.0 and cpu <= 100.0
    assert is_integer(fetched_at)
  end

  test "updates local CPU metric on subsequent ticks" do
    name = start_poller!(:poller_ticks, poll_interval: 50)

    {:ok, %{fetched_at: first_time}} = NodeCpuCache.get({name, node()})
    Process.sleep(100)
    {:ok, %{fetched_at: second_time}} = NodeCpuCache.get({name, node()})

    assert second_time > first_time
  end

  test "uses cpu_sup metric source when configured" do
    Application.ensure_all_started(:os_mon)
    name = start_poller!(:poller_cpu_sup, metric_source: :cpu_sup)

    assert {:ok, %{cpu: cpu}} = NodeCpuCache.get({name, node()})
    assert is_float(cpu)
    assert cpu >= 0.0 and cpu <= 100.0
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/rpc_load_balancer/selection_algorithm/least_cpu/poller_test.exs`
Expected: FAIL — module `Poller` does not exist.

- [ ] **Step 3: Implement the Poller GenServer**

Create `lib/rpc_load_balancer/load_balancer/selection_algorithm/least_cpu/poller.ex`:

```elixir
defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller do
  @moduledoc """
  GenServer that periodically samples local CPU and fetches remote node
  CPU metrics via `:erpc`, storing all results in `NodeCpuCache`.
  """

  use GenServer

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache

  @pg_group_name RpcLoadBalancer.LoadBalancer.Pg.pg_group_name()
  @remote_timeout :timer.seconds(2)

  @type state :: %{
          load_balancer_name: atom(),
          poll_interval: pos_integer(),
          metric_source: :scheduler_utilization | :cpu_sup
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :load_balancer_name)
    GenServer.start_link(__MODULE__, opts, name: :"#{name}_cpu_poller")
  end

  @impl true
  def init(opts) do
    state = %{
      load_balancer_name: Keyword.fetch!(opts, :load_balancer_name),
      poll_interval: Keyword.get(opts, :poll_interval, 5_000),
      metric_source: Keyword.get(opts, :metric_source, :scheduler_utilization)
    }

    {:ok, state, {:continue, :poll}}
  end

  @impl true
  def handle_continue(:poll, state) do
    sample_and_store_local(state)
    poll_remote_nodes(state)
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    sample_and_store_local(state)
    poll_remote_nodes(state)
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp sample_and_store_local(state) do
    cpu = sample_cpu(state.metric_source)
    now = System.monotonic_time(:millisecond)

    NodeCpuCache.put(
      {state.load_balancer_name, node()},
      nil,
      %{cpu: cpu, fetched_at: now}
    )
  end

  defp poll_remote_nodes(state) do
    remote_nodes = get_remote_members(state.load_balancer_name)

    Enum.each(remote_nodes, fn remote_node ->
      case fetch_remote_cpu(state.load_balancer_name, remote_node) do
        {:ok, %{cpu: cpu}} ->
          now = System.monotonic_time(:millisecond)

          NodeCpuCache.put(
            {state.load_balancer_name, remote_node},
            nil,
            %{cpu: cpu, fetched_at: now}
          )

        _error ->
          :ok
      end
    end)
  end

  defp get_remote_members(load_balancer_name) do
    try do
      @pg_group_name
      |> :pg.get_members(load_balancer_name)
      |> Enum.map(&node/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 === node()))
    catch
      _, _ -> []
    end
  end

  defp fetch_remote_cpu(load_balancer_name, remote_node) do
    :erpc.call(
      remote_node,
      NodeCpuCache,
      :get,
      [{load_balancer_name, remote_node}],
      @remote_timeout
    )
  catch
    _, _ -> :error
  end

  defp sample_cpu(:scheduler_utilization) do
    utilization = :scheduler.utilization(1)

    {total, count} =
      Enum.reduce(utilization, {0.0, 0}, fn
        {_scheduler_id, percent, _type}, {sum, n} when is_float(percent) ->
          {sum + percent, n + 1}

        {:total, percent, _type}, _acc ->
          {percent, 1}

        _, acc ->
          acc
      end)

    if count > 0 do
      total / count * 100.0
    else
      50.0
    end
  end

  defp sample_cpu(:cpu_sup) do
    case :cpu_sup.util() do
      percent when is_number(percent) -> percent / 1.0
      _ -> 50.0
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/rpc_load_balancer/selection_algorithm/least_cpu/poller_test.exs`
Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/rpc_load_balancer/load_balancer/selection_algorithm/least_cpu/poller.ex test/rpc_load_balancer/selection_algorithm/least_cpu/poller_test.exs
git commit -m "add: LeastCpu.Poller GenServer for CPU metric sampling"
```

---

### Task 5: Create LeastCpu Algorithm

**Files:**
- Create: `lib/rpc_load_balancer/load_balancer/selection_algorithm/least_cpu.ex`
- Create: `test/rpc_load_balancer/selection_algorithm/least_cpu_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/rpc_load_balancer/selection_algorithm/least_cpu_test.exs`:

```elixir
defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpuTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu

  defp start_lb!(name, opts \\ []) do
    default_opts = [
      name: name,
      selection_algorithm: LeastCpu,
      algorithm_opts: Keyword.merge([poll_interval: 60_000], opts)
    ]

    {:ok, _pid} = RpcLoadBalancer.start_link(default_opts)
    Process.sleep(100)
    name
  end

  defp seed_cpu!(name, metrics) do
    now = System.monotonic_time(:millisecond)

    Enum.each(metrics, fn {node_name, cpu} ->
      NodeCpuCache.put({name, node_name}, nil, %{cpu: cpu, fetched_at: now})
    end)
  end

  test "selects node with lowest CPU" do
    name = start_lb!(:lcpu_basic)
    nodes = [:node_a, :node_b, :node_c]
    seed_cpu!(name, node_a: 80.0, node_b: 20.0, node_c: 50.0)

    assert :node_b === LeastCpu.choose_from_nodes(name, nodes)
  end

  test "randomly selects among nodes within threshold" do
    name = start_lb!(:lcpu_threshold, cpu_threshold: 5.0)
    nodes = [:node_a, :node_b, :node_c]
    seed_cpu!(name, node_a: 22.0, node_b: 25.0, node_c: 50.0)

    results = Enum.map(1..100, fn _ -> LeastCpu.choose_from_nodes(name, nodes) end)
    unique = Enum.uniq(results)

    assert :node_a in unique
    assert :node_b in unique
    refute :node_c in unique
  end

  test "uses midpoint default (50.0) for nodes without cached CPU" do
    name = start_lb!(:lcpu_missing)
    nodes = [:node_a, :node_b]
    seed_cpu!(name, node_a: 60.0)

    assert :node_b === LeastCpu.choose_from_nodes(name, nodes)
  end

  test "on_node_change :left removes departed node metrics" do
    name = start_lb!(:lcpu_leave)
    seed_cpu!(name, node_a: 30.0, node_b: 40.0)

    :ok = LeastCpu.on_node_change(name, {:left, [:node_a]})

    assert {:ok, nil} === NodeCpuCache.get({name, :node_a})
    assert {:ok, %{cpu: 40.0}} = NodeCpuCache.get({name, :node_b})
  end

  test "on_node_change :joined is a no-op" do
    name = start_lb!(:lcpu_join)
    assert :ok === LeastCpu.on_node_change(name, {:joined, [:node_x]})
  end

  test "child_specs returns poller child spec" do
    specs = LeastCpu.child_specs(:test_lb, poll_interval: 5_000, metric_source: :scheduler_utilization)
    assert length(specs) === 1
    assert [%{id: _id, start: {RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller, :start_link, [_opts]}}] = specs
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/rpc_load_balancer/selection_algorithm/least_cpu_test.exs`
Expected: FAIL — module `LeastCpu` does not exist.

- [ ] **Step 3: Implement the LeastCpu algorithm**

Create `lib/rpc_load_balancer/load_balancer/selection_algorithm/least_cpu.ex`:

```elixir
defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu do
  @moduledoc """
  Least CPU node selection algorithm.

  Routes calls to the node with the lowest CPU utilization. A background
  `Poller` GenServer periodically samples local and remote CPU metrics,
  storing them in `NodeCpuCache`. Selection reads from cache, refreshes
  inline if stale, and randomly picks from nodes within a configurable
  threshold of the minimum.

  ## Usage

      RpcLoadBalancer.start_link(
        name: :my_lb,
        selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu,
        algorithm_opts: [
          poll_interval: 5_000,
          cpu_cache_ttl: 10_000,
          metric_source: :scheduler_utilization,
          cpu_threshold: 5.0
        ]
      )

  ## Options

    * `:poll_interval` - Background poll frequency in ms (default: `5_000`)
    * `:cpu_cache_ttl` - Max cache age before inline refresh in ms (default: `10_000`)
    * `:metric_source` - `:scheduler_utilization` or `:cpu_sup` (default: `:scheduler_utilization`)
    * `:cpu_threshold` - Band width in percentage points for "close enough" selection (default: `5.0`)
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  alias RpcLoadBalancer.LoadBalancer.NodeCpuCache
  alias RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.LeastCpu.Poller
  alias RpcLoadBalancer.LoadBalancer.ValueCache

  @default_cpu 50.0
  @remote_timeout :timer.seconds(2)

  @impl true
  def child_specs(load_balancer_name, opts) do
    poller_opts = [
      load_balancer_name: load_balancer_name,
      poll_interval: Keyword.get(opts, :poll_interval, 5_000),
      metric_source: Keyword.get(opts, :metric_source, :scheduler_utilization)
    ]

    [
      %{
        id: :"#{load_balancer_name}_cpu_poller",
        start: {Poller, :start_link, [poller_opts]}
      }
    ]
  end

  @impl true
  def init(load_balancer_name, opts) do
    ValueCache.put({load_balancer_name, :cpu_opts}, nil, %{
      cpu_cache_ttl: Keyword.get(opts, :cpu_cache_ttl, 10_000),
      cpu_threshold: Keyword.get(opts, :cpu_threshold, 5.0)
    })

    :ok
  end

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, _opts \\ []) do
    %{cpu_cache_ttl: ttl, cpu_threshold: threshold} = get_opts(load_balancer_name)
    now = System.monotonic_time(:millisecond)

    node_cpus =
      Enum.map(node_list, fn target_node ->
        cpu = get_node_cpu(load_balancer_name, target_node, now, ttl)
        {target_node, cpu}
      end)

    {_min_node, min_cpu} = Enum.min_by(node_cpus, &elem(&1, 1))

    node_cpus
    |> Enum.filter(fn {_node, cpu} -> cpu <= min_cpu + threshold end)
    |> Enum.random()
    |> elem(0)
  end

  @impl true
  def on_node_change(_load_balancer_name, {:joined, _nodes}), do: :ok

  def on_node_change(load_balancer_name, {:left, nodes}) do
    Enum.each(nodes, fn target_node ->
      NodeCpuCache.delete({load_balancer_name, target_node})
    end)

    :ok
  end

  defp get_node_cpu(load_balancer_name, target_node, now, ttl) do
    case NodeCpuCache.get({load_balancer_name, target_node}) do
      {:ok, %{cpu: cpu, fetched_at: fetched_at}} when now - fetched_at <= ttl ->
        cpu

      _ ->
        refresh_node_cpu(load_balancer_name, target_node, now)
    end
  end

  defp refresh_node_cpu(load_balancer_name, target_node, now) do
    case fetch_remote_cpu(load_balancer_name, target_node) do
      {:ok, %{cpu: cpu}} ->
        NodeCpuCache.put(
          {load_balancer_name, target_node},
          nil,
          %{cpu: cpu, fetched_at: now}
        )

        cpu

      _ ->
        @default_cpu
    end
  end

  defp fetch_remote_cpu(load_balancer_name, target_node) do
    :erpc.call(
      target_node,
      NodeCpuCache,
      :get,
      [{load_balancer_name, target_node}],
      @remote_timeout
    )
  catch
    _, _ -> :error
  end

  defp get_opts(load_balancer_name) do
    case ValueCache.get({load_balancer_name, :cpu_opts}) do
      {:ok, %{} = opts} -> opts
      _ -> %{cpu_cache_ttl: 10_000, cpu_threshold: 5.0}
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/rpc_load_balancer/selection_algorithm/least_cpu_test.exs`
Expected: All 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/rpc_load_balancer/load_balancer/selection_algorithm/least_cpu.ex test/rpc_load_balancer/selection_algorithm/least_cpu_test.exs
git commit -m "add: LeastCpu selection algorithm with threshold-based selection"
```

---

### Task 6: Add NodeCpuCache to Supervisor Cache List

**Files:**
- Modify: `lib/rpc_load_balancer.ex` (the `init/1` function, Cache child list)

- [ ] **Step 1: Add NodeCpuCache to the Cache child list**

In `lib/rpc_load_balancer.ex`, in the `init/1` function, add `RpcLoadBalancer.LoadBalancer.NodeCpuCache` to the Cache tuple's list. The Cache block should become:

```elixir
{Cache,
 [
   RpcLoadBalancer.LoadBalancer.IndexRegistry,
   RpcLoadBalancer.LoadBalancer.AlgorithmCache,
   RpcLoadBalancer.LoadBalancer.ValueCache,
   RpcLoadBalancer.LoadBalancer.DrainerCache,
   RpcLoadBalancer.LoadBalancer.CounterCache,
   RpcLoadBalancer.LoadBalancer.NodeCpuCache
 ]}
```

- [ ] **Step 2: Run full test suite**

Run: `mix test`
Expected: All tests pass (existing + new).

- [ ] **Step 3: Commit**

```bash
git add lib/rpc_load_balancer.ex
git commit -m "add: NodeCpuCache to supervisor cache list"
```

---

### Task 7: Integration Test — Full LeastCpu Lifecycle

**Files:**
- Modify: `test/rpc_load_balancer/selection_algorithm/least_cpu_test.exs`

- [ ] **Step 1: Add integration test for poller + algorithm working together**

Append the following test to `test/rpc_load_balancer/selection_algorithm/least_cpu_test.exs`:

```elixir
test "poller writes local CPU and algorithm reads it" do
  name = start_lb!(:lcpu_integration, poll_interval: 100)
  Process.sleep(200)

  {:ok, %{cpu: cpu}} = NodeCpuCache.get({name, node()})
  assert is_float(cpu)
  assert cpu >= 0.0 and cpu <= 100.0

  nodes = [node()]
  assert node() === LeastCpu.choose_from_nodes(name, nodes)
end

test "stale cache entry triggers inline refresh and falls back to midpoint default" do
  name = start_lb!(:lcpu_stale, poll_interval: 60_000, cpu_cache_ttl: 1)
  nodes = [:node_a, :node_b]
  now = System.monotonic_time(:millisecond)

  # node_a's entry is stale (5s old, ttl is 1ms), inline refresh will fail
  # (fake node), so node_a gets 50.0 midpoint default.
  # node_b has fresh data at 30.0, so node_b should be selected.
  NodeCpuCache.put({name, :node_a}, nil, %{cpu: 20.0, fetched_at: now - 5_000})
  NodeCpuCache.put({name, :node_b}, nil, %{cpu: 30.0, fetched_at: now})

  selected = LeastCpu.choose_from_nodes(name, nodes)
  assert selected === :node_b
end
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `mix test test/rpc_load_balancer/selection_algorithm/least_cpu_test.exs`
Expected: All 8 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add test/rpc_load_balancer/selection_algorithm/least_cpu_test.exs
git commit -m "add: integration tests for LeastCpu algorithm lifecycle"
```

---

### Task 8: Full Suite Verification

- [ ] **Step 1: Run full test suite**

Run: `mix test`
Expected: All tests pass with no warnings.

- [ ] **Step 2: Run compile check**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation.

- [ ] **Step 3: Run credo**

Run: `mix credo --strict`
Expected: No issues.

- [ ] **Step 4: Run dialyzer**

Run: `mix dialyzer`
Expected: No warnings.

- [ ] **Step 5: Commit any fixes from quality gates, if needed**
