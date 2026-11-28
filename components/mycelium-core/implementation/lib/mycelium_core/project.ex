defmodule Mycelium.Core.Project do
  @moduledoc "A Mycelium project backed by one git repository."
  use Ecto.Schema
  import Ecto.Changeset

  schema "projects" do
    field :name, :string
    field :repo_url, :string
    field :forge, :string, default: "github"
    field :default_branch, :string
    field :policy, :map, default: %{}

    has_many :users, Mycelium.Core.User
    has_many :agents, Mycelium.Core.Agent
    has_many :resources, Mycelium.Core.Resource
    has_many :connections, Mycelium.Core.Connection
    has_many :approvals, Mycelium.Core.Approval

    timestamps(type: :utc_datetime)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :repo_url, :forge, :default_branch, :policy])
    |> validate_required([:name, :repo_url, :default_branch])
    |> validate_policy()
  end

  defp validate_policy(changeset) do
    case get_field(changeset, :policy) do
      policy when is_map(policy) and not is_struct(policy) -> changeset
      _ -> add_error(changeset, :policy, "must be a map")
    end
  end
end
