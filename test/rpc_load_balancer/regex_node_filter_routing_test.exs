defmodule RpcLoadBalancer.RegexNodeFilterRoutingTest do
  # Distributed Erlang state is VM-global: peers and :net_kernel connections are
  # visible to every test in the VM, so this must not run async.
  use ExUnit.Case

  @primary_node :rpc_load_balancer_primary@localhost
  @prod_node :options_feed@localhost
  @lookalike_node :options_feed_kurt@localhost
  @anchored_filter ~r/^options_feed@/
  @substring_filter "options_feed"

  # Each scenario connects exactly one node, so there is only one candidate to
  # select and no randomness in the outcome. The call is :erlang.node/0, which
  # every node has and which returns whoever ran it, so the return value names
  # the node the call was dispatched to.
  setup_all do
    System.cmd("epmd", ["-daemon"])
    Node.start(@primary_node, :shortnames)

    on_exit(fn -> Node.stop() end)

    :ok
  end

  describe "when the cluster holds a node the filter is only a prefix of" do
    setup do
      start_peer(~c"options_feed_kurt")
    end

    test "an anchored Regex filter does not select it" do
      assert {:error, %ErrorMessage{code: :service_unavailable}} =
               RpcLoadBalancer.call_on_random_node(@anchored_filter, :erlang, :node, [],
                 call_directly?: false,
                 retry?: false
               )
    end

    test "the substring filter the Regex is built from does select it" do
      assert {:ok, @lookalike_node} ===
               RpcLoadBalancer.call_on_random_node(@substring_filter, :erlang, :node, [],
                 call_directly?: false,
                 retry?: false
               )
    end
  end

  describe "when the cluster holds the node the filter names exactly" do
    setup do
      start_peer(~c"options_feed")
    end

    test "an anchored Regex filter dispatches the call to it" do
      assert {:ok, @prod_node} ===
               RpcLoadBalancer.call_on_random_node(@anchored_filter, :erlang, :node, [],
                 call_directly?: false,
                 retry?: false
               )
    end
  end

  defp start_peer(name) do
    {:ok, _pid, node} = :peer.start_link(%{host: ~c"localhost", name: name, longnames: false})

    on_exit(fn -> Node.disconnect(node) end)

    %{peer: node}
  end
end
