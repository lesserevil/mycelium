defmodule Mycelium.Core.Agent do
  @moduledoc "An agent working on a project, implicitly trusted on addition."
  use Ecto.Schema
  import Ecto.Changeset

  schema "agents" do
    field :name, :string
    field :is_main, :boolean, default: false

    belongs_to :project, Mycelium.Core.Project
    belongs_to :owner, Mycelium.Core.User, foreign_key: :owner_user_id
    belongs_to :added_by, Mycelium.Core.User, foreign_key: :added_by_user_id
    has_one :sandbox, Mycelium.Core.Sandbox, foreign_key: :subject_id,
      where: [subject_type: :agent]

    timestamps(type: :utc_datetime)
  end

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:name, :is_main, :project_id, :owner_user_id, :added_by_user_id])
    |> validate_required([:name, :project_id, :owner_user_id, :added_by_user_id])
    |> unique_constraint([:project_id, :name])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:owner_user_id)
    |> foreign_key_constraint(:added_by_user_id)
  end
end
