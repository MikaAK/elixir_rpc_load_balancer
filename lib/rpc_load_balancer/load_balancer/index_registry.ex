defmodule RpcLoadBalancer.LoadBalancer.IndexRegistry do
  @moduledoc """
  Assigns unique integer indices to arbitrary keys for a given cache.

  Uses `Cache.PersistentTerm` for key-to-index mappings and `:atomics`
  for a monotonic next-index counter per cache. Indices are zero-based
  and never reused.
  """

  use Cache,
    adapter: Cache.PersistentTerm,
    name: :rpc_lb_index_registry,
    sandbox?: false,
    opts: []

  @spec init_counter(atom()) :: :ok
  def init_counter(cache_name) do
    pt_key = {__MODULE__, :counter, cache_name}

    try do
      :persistent_term.get(pt_key)
      :ok
    rescue
      ArgumentError ->
        :persistent_term.put(pt_key, :atomics.new(1, []))
        :ok
    end
  end

  @spec get_or_register(atom(), term()) :: non_neg_integer()
  def get_or_register(cache_name, key) do
    registry_key = {cache_name, key}

    case get(registry_key) do
      {:ok, index} when not is_nil(index) ->
        index

      _ ->
        ref = :persistent_term.get({__MODULE__, :counter, cache_name})
        index = :atomics.add_get(ref, 1, 1) - 1
        :ok = put(registry_key, nil, index)
        index
    end
  end
end
