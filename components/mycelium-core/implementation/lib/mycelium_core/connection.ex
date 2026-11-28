defmodule Mycelium.Core.Connection do
  @moduledoc """
  A managed tailcat connection from one agent to an agent or resource.
  State machine: requested -> active -> revoked | closed.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "connections" do
    field :destination_type, Ecto.Enum, values: [:agent, :resource]
    field :destination_id, :integer
    field :protocol, :string
    field :state, Ecto.Enum, values: [:requested, :active, :revoked, :closed]
    # tailcat custody: the bearer address and its scope, per connection.
    field :tailcat, :map

    belongs_to :project, Mycelium.Core.Project
    belongs_to :source_agent, Mycelium.Core.Agent, foreign_key: :source_agent_id
    belongs_to :approved_by, Mycelium.Core.User, foreign_key: :approved_by_user_id

    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:destination_type, :destination_id, :protocol, :state, :tailcat,
                    :project_id, :source_agent_id, :approved_by_user_id])
    |> validate_required([:destination_type, :destination_id, :protocol, :state,
                          :project_id, :source_agent_id])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:source_agent_id)
  end
end
