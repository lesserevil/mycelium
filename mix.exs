defmodule Mycelium.MixProject do
  use Mix.Project

  def project do
    [
      app: :mycelium,
      version: "0.1.0",
      elixir: "~> 1.18",
      description:
        "Project-level, multi-user manager for agent and container sandboxes, with managed tailcat interconnects and centrally managed sandbox configuration.",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Mycelium.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
