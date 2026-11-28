import Config

config :mycelium_core, Mycelium.Core.Repo,
  database: "mycelium_core_test",
  username: "mycelium",
  password: "mycelium",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

# Bearer token off in tests; endpoint tests exercise both modes explicitly.
config :mycelium_service, bearer_token: nil

# Port 0 lets the OS pick a free port when the app boots in tests.
config :mycelium_service, http_port: 0
