defmodule RpcLoadBalancer.LoadBalancer.IndexRegistryTest do
  use ExUnit.Case

  alias RpcLoadBalancer.LoadBalancer.IndexRegistry

  setup do
    start_supervised!({Cache, [IndexRegistry]})
    Process.sleep(50)
    :ok
  end

  describe "get_or_register/2" do
    test "assigns zero-based incrementing indices once the counter is initialized" do
      IndexRegistry.init_counter(:index_registry_test_ok)

      assert 0 === IndexRegistry.get_or_register(:index_registry_test_ok, :first)
      assert 1 === IndexRegistry.get_or_register(:index_registry_test_ok, :second)
      assert 0 === IndexRegistry.get_or_register(:index_registry_test_ok, :first)
    end

    test "raises an actionable error when the counter was never initialized" do
      error =
        assert_raise RuntimeError, fn ->
          IndexRegistry.get_or_register(:index_registry_test_missing, :key)
        end

      assert error.message =~ "no index counter is registered"
      assert error.message =~ inspect(:index_registry_test_missing)
      assert error.message =~ "init_counter/1"
      assert error.message =~ ":load_balancer"
    end
  end
end
