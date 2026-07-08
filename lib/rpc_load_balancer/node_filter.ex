defmodule RpcLoadBalancer.NodeFilter do
  @moduledoc """
  Node-name matching for filter-based routing and load-balancer membership.

  A node matches a filter when the filter is a substring of (or regex against)
  the node name, EXCEPT when the node's short name carries a configured excluded
  pattern that the filter itself does not. This keeps a class of nodes — e.g. QA
  nodes named `<type>_qa@host` — out of the general `<type>` routing set, while a
  `<type>_qa` filter can still reach them.

  Exclusions default to `[]` (no behavior change). Configure them with:

      config :rpc_load_balancer, excluded_node_patterns: ["_qa"]
  """

  @spec matches?(node() | String.t(), String.t() | Regex.t()) :: boolean()
  @spec matches?(node() | String.t(), String.t() | Regex.t(), [String.t()]) :: boolean()
  def matches?(node_name, filter, excluded_patterns \\ RpcLoadBalancer.Config.excluded_node_patterns()) do
    name = to_string(node_name)
    name =~ filter and not excluded_from_filter?(name, filter, excluded_patterns)
  end

  defp excluded_from_filter?(name, filter, excluded_patterns) do
    Enum.any?(excluded_patterns, fn pattern ->
      node_has_pattern?(name, pattern) and not filter_has_pattern?(filter, pattern)
    end)
  end

  defp node_has_pattern?(name, pattern) do
    name |> node_short_name() |> String.contains?(pattern)
  end

  defp filter_has_pattern?(filter, pattern) when is_binary(filter) do
    String.contains?(filter, pattern)
  end

  defp filter_has_pattern?(%Regex{} = filter, pattern) do
    String.contains?(Regex.source(filter), pattern)
  end

  defp node_short_name(name), do: name |> String.split("@") |> hd()
end
