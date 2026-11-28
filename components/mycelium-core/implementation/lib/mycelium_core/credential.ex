defmodule Mycelium.Core.Credential do
  @moduledoc "One repository credential (ssh_key or api_key) owned by a user."
  use Ecto.Schema
  import Ecto.Changeset

  schema "credentials" do
    field :kind, Ecto.Enum, values: [:ssh_key, :api_key]
    # Provider material or reference consumable by sandbox orchestration.
    field :material, :string

    belongs_to :user, Mycelium.Core.User

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:kind, :material, :user_id])
    |> validate_required([:kind, :user_id])
    |> foreign_key_constraint(:user_id)
  end
end
