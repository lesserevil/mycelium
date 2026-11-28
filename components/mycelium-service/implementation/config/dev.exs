import Config

config :mycelium_core, Mycelium.Core.Repo,
  database: "mycelium_dev",
  username: "mycelium",
  password: "mycelium",
  hostname: "localhost"

config :mycelium_service, http_port: 4000
