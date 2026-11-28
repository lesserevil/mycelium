# The application boots its own Repo (application module); start one only if
# the app didn't.
case Mycelium.Core.Repo.start_link() do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

path = Application.app_dir(:mycelium_core, "priv/repo/migrations")
Ecto.Migrator.run(Mycelium.Core.Repo, path, :up, all: true)

Ecto.Adapters.SQL.Sandbox.mode(Mycelium.Core.Repo, :manual)
ExUnit.start()
