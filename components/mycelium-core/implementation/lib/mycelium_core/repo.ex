defmodule Mycelium.Core.Repo do
  use Ecto.Repo,
    otp_app: :mycelium_core,
    adapter: Ecto.Adapters.Postgres
end
