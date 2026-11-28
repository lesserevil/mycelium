defmodule Mycelium.Core.Repo.Migrations.CreateMyceliumCoreTables do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :repo_url, :string, null: false
      add :forge, :string, null: false, default: "github"
      add :default_branch, :string, null: false
      add :policy, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create table(:users) do
      add :forge_login, :string, null: false
      add :approved, :boolean, null: false, default: false
      add :approved_by_user_id, references(:users, on_delete: :nilify_all)
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:users, [:project_id])

    create table(:credentials) do
      add :kind, :text, null: false
      add :material, :text
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:credentials, [:user_id])

    create table(:agents) do
      add :name, :string, null: false
      add :is_main, :boolean, null: false, default: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :owner_user_id, references(:users, on_delete: :nilify_all), null: false
      add :added_by_user_id, references(:users, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agents, [:project_id, :name])

    create table(:resources) do
      add :name, :string, null: false
      add :kind, :string, null: false
      add :protocol, :string, null: false
      add :config, :map, null: false, default: %{}
      add :created_via, :text, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :requested_by_agent_id, references(:agents, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:resources, [:project_id, :name])

    create table(:sandboxes) do
      add :subject_type, :text, null: false
      add :subject_id, :integer, null: false
      add :gateway_sandbox_name, :string
      add :image, :string
      add :gateway_state, :map
      add :state_cached_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:sandboxes, [:subject_type, :subject_id])

    create table(:connections) do
      add :destination_type, :text, null: false
      add :destination_id, :integer, null: false
      add :protocol, :string, null: false
      add :state, :text, null: false
      add :tailcat, :map
      add :approved_by_user_id, references(:users, on_delete: :nilify_all)
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :source_agent_id, references(:agents, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:connections, [:project_id])

    create table(:approvals) do
      add :kind, :text, null: false
      add :requester_type, :text, null: false
      add :requester_id, :integer, null: false
      add :payload, :map, null: false, default: %{}
      add :status, :text, null: false
      add :decided_by_user_id, references(:users, on_delete: :nilify_all)
      add :decided_at, :utc_datetime
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:approvals, [:project_id, :status])
  end
end
