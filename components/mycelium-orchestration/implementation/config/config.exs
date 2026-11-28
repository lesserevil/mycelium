import Config

# The orchestration library drives the core domain's Repo; in this projection
# the Repo configuration lives with the host application. Tests configure it
# below.
config :mycelium_core, ecto_repos: [Mycelium.Core.Repo]

import_config "#{config_env()}.exs"
