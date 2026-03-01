defmodule PklElixir.MixProject do
  use Mix.Project

  @version "0.0.3"
  @source_url "https://github.com/typesend/pkl-elixir"

  def project do
    [
      app: :pkl_elixir,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "Pkl language integration for Elixir — evaluator client and code generation.",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:msgpax, "~> 2.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "usage",
      extras: ["guides/usage.md", "README.md"]
    ]
  end
end
