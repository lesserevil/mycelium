defmodule Mycelium.Core.Sandbox do
  @moduledoc """
  The one runtime binding for an agent or resource. Gateway state is a cached
  projection observed at `state_cached_at`; never authority.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "sandboxes" do
    field :subject_type, Ecto.Enum, values: [:agent, :resource]
    field :subject_id, :integer
    field :gateway_sandbox_name, :string
    field :image, :string
    field :gateway_state, :map
    field :state_cached_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(sandbox, attrs) do
    sandbox
    |> cast(attrs, [:subject_type, :subject_id, :gateway_sandbox_name, :image,
                    :gateway_state, :state_cached_at])
    |> validate_required([:subject_type, :subject_id])
    |> validate_subject()
  end

  defp validate_subject(changeset) do
    case {get_field(changeset, :subject_type), get_field(changeset, :subject_id)} do
      {type, id} when type in [:agent, :resource] and is_integer(id) -> changeset
      _ -> add_error(changeset, :subject_id, "must reference the declared subject")
    end
  end
end
