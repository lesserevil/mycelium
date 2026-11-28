import Config

config :mycelium_core, ecto_repos: [Mycelium.Core.Repo]

import_config "#{config_env()}.exs"
