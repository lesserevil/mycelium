defmodule Mycelium.Core.Approval do
  @moduledoc "One row per human decision the trust rules route to a user."
  use Ecto.Schema
  import Ecto.Changeset

  schema "approvals" do
    field :kind, Ecto.Enum, values: [:add_agent, :add_resource, :connect_agents]
    field :requester_type, Ecto.Enum, values: [:agent, :user]
    field :requester_id, :integer
    field :payload, :map, default: %{}
    field :status, Ecto.Enum, values: [:pending, :approved, :denied]
    field :decided_at, :utc_datetime

    belongs_to :project, Mycelium.Core.Project
    belongs_to :decided_by, Mycelium.Core.User, foreign_key: :decided_by_user_id

    timestamps(type: :utc_datetime)
  end

  def changeset(approval, attrs) do
    approval
    |> cast(attrs, [:kind, :requester_type, :requester_id, :payload, :status,
                    :decided_by_user_id, :decided_at, :project_id])
    |> validate_required([:kind, :requester_type, :requester_id, :status, :project_id])
    |> foreign_key_constraint(:project_id)
  end
end
