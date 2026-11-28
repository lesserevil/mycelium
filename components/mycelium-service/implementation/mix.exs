# Synthesized Mix authority (dev projection). The declarative intent lives in
# mix-project.json; core and orchestration resolve as retained provider roots
# in the authorized lifecycle, and as path deps here.
defmodule MyceliumService.MixProject do
  use Mix.Project

  def project do
    [
      app: :mycelium_service,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MyceliumService.Application, []}
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:mycelium_core, path: "../../mycelium-core/implementation"},
      {:mycelium_orchestration, path: "../../mycelium-orchestration/implementation"}
    ]
  end
end
