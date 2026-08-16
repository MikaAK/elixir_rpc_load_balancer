defmodule RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing do
  @moduledoc """
  Consistent hash ring node selection algorithm powered by `libring`.

  Routes requests to nodes based on a caller-provided `:key` option.
  Each physical node is placed on the ring as virtual nodes (shards)
  so that topology changes only redistribute a minimal number of keys.

  Supports replica selection via `choose_nodes/4` — returns multiple
  distinct nodes for a given key, useful for replication strategies.

  When no key is provided, falls back to random selection.

  Storage:
    * `:weight` (compile-time-ish — set once at `init/2`) lives in
      `:persistent_term` keyed by `{__MODULE__, lb_name, :weight}`.
      Write-once is the access pattern `:persistent_term` is designed
      for.
    * The ring itself lives in `HashRingCache` (ETS). It's rewritten
      on every `on_node_change` event, so PT would mean continuous
      global GC sweeps in clusters with steady flapping.

  ## Usage

      RpcLoadBalancer.start_link(
        name: :my_balancer,
        selection_algorithm: RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing,
        algorithm_opts: [weight: 200]
      )

      RpcLoadBalancer.select_node(:my_balancer, key: "user:123")

      # Replica selection goes through the dispatch layer:
      {:ok, members} = RpcLoadBalancer.get_members(:my_balancer)

      [primary, replica] =
        RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.choose_nodes(
          RpcLoadBalancer.LoadBalancer.SelectionAlgorithm.HashRing,
          :my_balancer,
          members,
          2,
          key: "user:123"
        )

  ## Options

  - `:weight` — number of virtual nodes (shards) per physical node (default: 128)
  """

  @behaviour RpcLoadBalancer.LoadBalancer.SelectionAlgorithm

  alias RpcLoadBalancer.LoadBalancer.HashRingCache

  @default_weight 128

  @impl true
  def caches, do: [HashRingCache]

  @impl true
  def init(load_balancer_name, opts) do
    weight = Keyword.get(opts, :weight, @default_weight)
    :persistent_term.put(weight_pt_key(load_balancer_name), weight)
    HashRingCache.delete_ring(load_balancer_name)
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
    HashRingCache.delete_ring(load_balancer_name)
    :ok
  end

  defp get_or_build_ring(load_balancer_name, node_list) do
    case HashRingCache.get_ring(load_balancer_name) do
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

    HashRingCache.put_ring(load_balancer_name, ring)
    ring
  end

  defp weight_pt_key(load_balancer_name), do: {__MODULE__, load_balancer_name, :weight}

  defp get_weight(load_balancer_name) do
    :persistent_term.get(weight_pt_key(load_balancer_name), @default_weight)
  end
end
