{:ok, _} = Mycelium.Core.Repo.start_link()

path = Application.app_dir(:mycelium_core, "priv/repo/migrations")
Ecto.Migrator.run(Mycelium.Core.Repo, path, :up, all: true)

Ecto.Adapters.SQL.Sandbox.mode(Mycelium.Core.Repo, :manual)
ExUnit.start()
