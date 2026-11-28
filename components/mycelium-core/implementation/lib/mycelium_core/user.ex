defmodule Mycelium.Core.User do
  @moduledoc "A developer trust root within one project."
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :forge_login, :string
    field :approved, :boolean, default: false
    field :approved_by_user_id, :integer

    belongs_to :project, Mycelium.Core.Project
    has_many :credentials, Mycelium.Core.Credential

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:forge_login, :approved, :approved_by_user_id, :project_id])
    |> validate_required([:forge_login, :project_id])
    |> foreign_key_constraint(:project_id)
  end
end
