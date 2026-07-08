defmodule RpcLoadBalancer.NodeFilterTest do
  use ExUnit.Case, async: true

  alias RpcLoadBalancer.NodeFilter

  describe "&matches?/3 with no excluded patterns (default behavior)" do
    test "matches by substring, exactly as plain =~ did" do
      assert NodeFilter.matches?(:options_feed@host, "options_feed", [])
      assert NodeFilter.matches?(:options_feed_1@host, "options_feed", [])
      assert NodeFilter.matches?(:cfx_web_2@host, "web", [])
      refute NodeFilter.matches?(:cfx_web@host, "options_feed", [])
    end

    test "supports a Regex filter" do
      assert NodeFilter.matches?(:options_feed@host, ~r/^options_feed@/, [])
      refute NodeFilter.matches?(:gamma_feed@host, ~r/^options_feed@/, [])
    end
  end

  describe "&matches?/3 with an excluded pattern" do
    @patterns ["_qa"]

    test "a prod filter does NOT match a node carrying the excluded pattern" do
      refute NodeFilter.matches?(:options_feed_qa@host, "options_feed", @patterns)
      refute NodeFilter.matches?(:options_feed_qa_1@host, "options_feed", @patterns)
    end

    test "a filter that itself carries the pattern still matches the excluded node" do
      assert NodeFilter.matches?(:options_feed_qa@host, "options_feed_qa", @patterns)
    end

    test "nodes without the excluded pattern are unaffected" do
      assert NodeFilter.matches?(:options_feed@host, "options_feed", @patterns)
      assert NodeFilter.matches?(:options_feed_1@host, "options_feed", @patterns)
    end

    test "the pattern is only honored in the node short name, not the hostname" do
      assert NodeFilter.matches?(:"options_feed@host_qa", "options_feed", @patterns)
    end
  end
end
