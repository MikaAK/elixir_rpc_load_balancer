defmodule RpcLoadBalancer.MixProject do
  use Mix.Project

  def project do
    [
      app: :rpc_load_balancer,
      version: "0.3.1",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
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
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
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
      extra_applications: [:logger, :os_mon],
      mod: {RpcLoadBalancer.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:error_message, "~> 0.3"},
      {:elixir_cache, ">= 0.4.8"},
      {:elixir_skills, "~> 0.1", optional: true, only: [:test, :dev]},
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},

      {:libring, "~> 1.7"},
      {:castore, "~> 1.0"},

      {:benchee, "~> 1.3", only: :dev, runtime: false},

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
      source_url: "https://github.com/MikaAK/rpc_load_balancer",
      extras: [
        "docs/overview.md",
        "docs/tutorials/getting-started.md",
        "docs/how-to/custom-selection-algorithm.md",
        "docs/how-to/hash-based-routing.md",
        "docs/how-to/node-filtering.md",
        "docs/how-to/connection-tracking.md",
        "docs/how-to/weighted-round-robin.md",
        "docs/how-to/testing-with-call-direct.md",
        "docs/reference/load_balancer.md",
        "docs/explanation/architecture.md"
      ],
      groups_for_extras: [
        Tutorials: ~r/docs\/tutorials\/.*/,
        "How-To Guides": ~r/docs\/how-to\/.*/,
        Reference: ~r/docs\/reference\/.*/,
        Explanation: ~r/docs\/explanation\/.*/
      ]
    ]
  end
end
