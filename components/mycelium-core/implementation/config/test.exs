import Config

config :mycelium_core, Mycelium.Core.Repo,
  database: "mycelium_core_test",
  username: "mycelium",
  password: "mycelium",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
