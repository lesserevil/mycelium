defmodule Openshell.MixProject do
  use Mix.Project
  def project do
    [
      app: :openshell,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [{:grpc, "~> 0.10"}, {:protobuf, "~> 0.14"}]
    ]
  end
  def application, do: [extra_applications: [:logger]]
end
