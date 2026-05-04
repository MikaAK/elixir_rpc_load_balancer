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
    sandbox?: Mix.env() === :test,
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

  @doc """
  Read the index for a key without telemetry overhead.

  Goes directly to the configured cache adapter, skipping the
  `:telemetry.span/3`-wrapped `Cache.get/1`. Returns `nil` when the
  key has never been registered.

  Companion to `get_or_register/2` — use this when callers must not
  allocate a new index on miss.
  """
  @spec get_index(atom(), term()) :: non_neg_integer() | nil
  def get_index(cache_name, key) do
    case cache_adapter().get(@cache_name, {cache_name, key}) do
      {:ok, nil} -> nil
      {:ok, value} -> Cache.TermEncoder.decode(value)
      _ -> nil
    end
  end
end
