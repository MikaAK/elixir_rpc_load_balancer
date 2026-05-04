defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing do
  @moduledoc """
  Consistent hash ring node selection algorithm powered by `libring`.

  Routes requests to nodes based on a caller-provided `:key` option.
  Each physical node is placed on the ring as virtual nodes (shards)
  so that topology changes only redistribute a minimal number of keys.

  Supports replica selection via `choose_nodes/4` — returns multiple
  distinct nodes for a given key, useful for replication strategies.

  When no key is provided, falls back to random selection.

  The ring is stored directly in `:persistent_term` so that the read
  path on every selection is a single zero-copy term lookup with no
  process hops, no ETS contention, and no telemetry-span wrapping.
  Topology-change events trigger a `:persistent_term.put/2`, which is
  costly (it walks every process referencing the term table), but
  topology change is rare and selection happens millions of times
  per second — the asymmetry matches `:persistent_term`'s design.

  ## Usage

      RpcLoadBalancer.LoadBalancer.start_link(
        name: :my_balancer,
        selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing,
        algorithm_opts: [weight: 200]
      )

      RpcLoadBalancer.LoadBalancer.select_node(:my_balancer, key: "user:123")

      {:ok, [primary, replica]} =
        RpcLoadBalancer.LoadBalancer.select_nodes(:my_balancer, 2, key: "user:123")

  ## Options

  - `:weight` — number of virtual nodes (shards) per physical node (default: 128)
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  alias RpcLoadBalancer.LoadBalancer.LoadBalancerOptsCache

  @default_weight 128

  @impl true
  def init(load_balancer_name, opts) do
    weight = Keyword.get(opts, :weight, @default_weight)
    LoadBalancerOptsCache.put({load_balancer_name, :hash_ring_weight}, nil, weight)
    erase_ring(load_balancer_name)
    :ok
  end

  @impl true
  def choose_from_nodes(load_balancer_name, node_list, opts \\ []) do
    case Keyword.get(opts, :key) do
      nil ->
        Enum.random(node_list)

      key ->
        ring = get_or_build_ring(load_balancer_name, node_list)
        HashRing.key_to_node(ring, key)
    end
  end

  @impl true
  def choose_nodes(load_balancer_name, node_list, count, opts) do
    case Keyword.get(opts, :key) do
      nil ->
        node_list
        |> Enum.shuffle()
        |> Enum.take(count)

      key ->
        ring = get_or_build_ring(load_balancer_name, node_list)
        HashRing.key_to_nodes(ring, key, count)
    end
  end

  @impl true
  def on_node_change(load_balancer_name, {_event, _nodes}) do
    erase_ring(load_balancer_name)
    :ok
  end

  defp get_or_build_ring(load_balancer_name, node_list) do
    case :persistent_term.get(ring_pt_key(load_balancer_name), nil) do
      nil -> rebuild_ring(load_balancer_name, node_list)
      ring -> ring
    end
  end

  defp rebuild_ring(load_balancer_name, node_list) do
    weight = get_weight(load_balancer_name)

    ring =
      Enum.reduce(node_list, HashRing.new(), fn node, ring ->
        HashRing.add_node(ring, node, weight)
      end)

    :persistent_term.put(ring_pt_key(load_balancer_name), ring)
    ring
  end

  defp erase_ring(load_balancer_name) do
    _ = :persistent_term.erase(ring_pt_key(load_balancer_name))
    :ok
  end

  defp ring_pt_key(load_balancer_name), do: {__MODULE__, load_balancer_name}

  defp get_weight(load_balancer_name) do
    case LoadBalancerOptsCache.read({load_balancer_name, :hash_ring_weight}) do
      nil -> @default_weight
      weight -> weight
    end
  end
end
