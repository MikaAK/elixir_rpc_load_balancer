defmodule RpcLoadBalancer.MixProject do
  use Mix.Project

  def project do
    [
      app: :rpc_load_balancer,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "RPC wrappers with a node load balancer",
      docs: docs(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix, :credo, :jason],
        list_unused_filters: true,
        plt_local_path: ".dialyzer",
        plt_core_path: ".dialyzer",
        flags: [:unmatched_returns]
      ],
      preferred_cli_env: [
        dialyzer: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {RpcLoadBalancer.Application, []}
    ]
  end

  defp deps do
    [
      {:error_message, "~> 0.3"},
      {:elixir_cache, github: "MikaAK/elixir_cache", branch: "ets-rehydration"},
      {:castore, "~> 1.0"},

      {:credo, "~> 1.6", only: [:test, :dev], runtime: false},
      {:blitz_credo_checks, "~> 0.1", only: [:test, :dev], runtime: false},

      {:excoveralls, "~> 0.10", only: :test, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", optional: true, only: :test, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Mika Kalathil"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/MikaAK/rpc_load_balancer"},
      files: ~w(mix.exs README.md CHANGELOG.md lib docs)
    ]
  end

  defp docs do
    [
      main: "overview",
      source_url: "https://github.com/MikaAK/rpc_load_balancer"
    ]
  end
end
