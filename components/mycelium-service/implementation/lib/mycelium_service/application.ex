defmodule MyceliumService.Application do
  @moduledoc """
  The running Mycelium service: the core domain's Repo plus the
  supervisor-protocol HTTP endpoint.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Mycelium.Core.Repo,
      {Bandit,
       plug: Mycelium.Service.Endpoint,
       port: Application.get_env(:mycelium_service, :http_port, 4000)}
    ]

    opts = [strategy: :one_for_one, name: MyceliumService.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
