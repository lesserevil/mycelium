# Synthesized Mix authority (dev projection). The declarative intent lives in
# mix-project.json; this projection is disposable and re-derivable.
defmodule MyceliumCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :mycelium_core,
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
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.21"},
      {:jason, "~> 1.4"}
    ]
  end
end
