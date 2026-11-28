defmodule Mycelium.Core.Resource do
  @moduledoc "A project resource (database, service, tool) backed by a sandbox."
  use Ecto.Schema
  import Ecto.Changeset

  schema "resources" do
    field :name, :string
    field :kind, :string
    field :protocol, :string
    field :config, :map, default: %{}
    field :created_via, Ecto.Enum, values: [:policy_auto, :approval]

    belongs_to :project, Mycelium.Core.Project
    belongs_to :requested_by, Mycelium.Core.Agent, foreign_key: :requested_by_agent_id
    has_one :sandbox, Mycelium.Core.Sandbox, foreign_key: :subject_id,
      where: [subject_type: :resource]

    timestamps(type: :utc_datetime)
  end

  def changeset(resource, attrs) do
    resource
    |> cast(attrs, [:name, :kind, :protocol, :config, :created_via, :project_id,
                    :requested_by_agent_id])
    |> validate_required([:name, :kind, :protocol, :created_via, :project_id])
    |> unique_constraint([:project_id, :name])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:requested_by_agent_id)
  end
end
