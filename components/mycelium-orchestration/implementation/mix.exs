# Synthesized Mix authority (dev projection). The declarative intent lives in
# mix-project.json; the core and openshell-elixir capabilities resolve as
# retained provider roots in the authorized lifecycle, and as path deps here.
defmodule MyceliumOrchestration.MixProject do
  use Mix.Project

  def project do
    [
      app: :mycelium_orchestration,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:mycelium_core, path: "../../mycelium-core/implementation"},
      {:openshell, path: "../../openshell-elixir/implementation"}
    ]
  end
end
