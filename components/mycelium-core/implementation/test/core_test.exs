defmodule Mycelium.CoreTest do
  use ExUnit.Case, async: true

  import Ecto.Adapters.SQL.Sandbox, only: [start_owner!: 2, stop_owner: 1]

  alias Mycelium.Core
  alias Mycelium.Core.Repo
  alias Mycelium.Core.{Agent, Approval, Connection, Resource, User}

  setup do
    owner = start_owner!(Mycelium.Core.Repo, shared: false)
    on_exit(fn -> stop_owner(owner) end)
    :ok
  end

  defp project!(policy \\ %{}) do
    {:ok, project} =
      Core.create_project(%{
        "name" => "proj-#{System.unique_integer([:positive])}",
        "repo_url" => "https://github.com/lesserevil/mycelium",
        "default_branch" => "main",
        "policy" => policy
      })

    project
  end

  defp bootstrap_user!(project) do
    {:ok, user} = Core.add_user(project, %{"forge_login" => "shedwards"})
    user
  end

  defp agent!(project, user, name) do
    {:ok, agent} = Core.add_agent(project, user, %{"name" => name})
    agent
  end

  # Users are the trust roots ------------------------------------------------

  test "first user is self-approved; second user without approver is rejected" do
    project = project!()
    first = bootstrap_user!(project)

    assert first.approved and first.approved_by_user_id == first.id

    {:error, changeset} = Core.add_user(project, %{"forge_login" => "other"})
    assert "must reference an approved user of the project" in errors_on(changeset)

    {:ok, second} =
      Core.add_user(project, %{"forge_login" => "other", "approved_by_user_id" => first.id})

    assert second.approved and second.approved_by_user_id == first.id
  end

  test "credentials attach to a user" do
    project = project!()
    user = bootstrap_user!(project)

    {:ok, credential} =
      Core.add_credential(user, %{"kind" => :ssh_key, "material" => "ssh-ed25519 AAA..."})

    assert credential.kind == :ssh_key and credential.user_id == user.id
  end

  # Agents are implicitly trusted on addition --------------------------------

  test "approved user adds an agent; duplicate name is rejected" do
    project = project!()
    user = bootstrap_user!(project)

    {:ok, agent} = Core.add_agent(project, user, %{"name" => "main"})
    assert agent.owner_user_id == user.id and agent.added_by_user_id == user.id

    {:error, changeset} = Core.add_agent(project, user, %{"name" => "main"})
    assert "has already been taken" in errors_on(changeset)
  end

  test "unapproved owner cannot add an agent" do
    project = project!()
    user = bootstrap_user!(project)
    Repo.update!(Ecto.Changeset.change(user, approved: false))

    assert {:error, _} = Core.add_agent(project, user, %{"name" => "rogue"})
  end

  # Resource creation is policy-gated auto -----------------------------------

  test "within-policy request auto-creates resource and sandbox row" do
    policy = %{"resource_count_limit" => 1, "image_allowlist" => ["nvcr.io/nvidia/base/ubuntu:24.04"]}
    project = project!(policy)
    user = bootstrap_user!(project)
    agent = agent!(project, user, "main")

    {:ok, resource, :policy_auto} =
      Core.request_resource(project, agent, %{
        "name" => "db",
        "kind" => "database",
        "protocol" => "postgres",
        "image" => "nvcr.io/nvidia/base/ubuntu:24.04"
      })

    assert resource.created_via == :policy_auto
    assert sandbox = Mycelium.Core.Repo.get_by(Mycelium.Core.Sandbox, subject_type: :resource, subject_id: resource.id)
    assert sandbox.image == "nvcr.io/nvidia/base/ubuntu:24.04"
  end

  test "beyond-policy request queues an approval; approving creates the resource" do
    policy = %{"resource_count_limit" => 1, "image_allowlist" => ["nvcr.io/nvidia/base/ubuntu:24.04"]}
    project = project!(policy)
    user = bootstrap_user!(project)
    agent = agent!(project, user, "main")

    attrs = %{"name" => "db", "kind" => "database", "protocol" => "postgres",
              "image" => "nvcr.io/nvidia/base/ubuntu:24.04"}
    {:ok, _first, :policy_auto} = Core.request_resource(project, agent, attrs)
    {:ok, approval, :queued} =
      Core.request_resource(project, agent, Map.put(attrs, "name", "db2"))

    assert approval.kind == :add_resource and approval.status == :pending

    {:ok, %{resource: resource}} = Core.decide_approval(approval, user, :approved)
    assert resource.created_via == :approval

    {:error, changeset} = Core.decide_approval(approval, user, :approved)
    assert "has already been decided (approved)" in errors_on(changeset)
  end

  test "image outside the allowlist queues even within the count limit" do
    policy = %{"resource_count_limit" => 5, "image_allowlist" => ["nvcr.io/nvidia/base/ubuntu:24.04"]}
    project = project!(policy)
    user = bootstrap_user!(project)
    agent = agent!(project, user, "main")

    {:ok, approval, :queued} =
      Core.request_resource(project, agent, %{"name" => "x", "kind" => "tool",
                                              "protocol" => "tcp", "image" => "unknown/image"})

    assert approval.status == :pending
  end

  # Connections follow the three approval rules -------------------------------

  test "agent to resource auto-approves with the resource's protocol" do
    policy = %{"image_allowlist" => ["nvcr.io/nvidia/base/ubuntu:24.04"]}
    project = project!(policy)
    user = bootstrap_user!(project)
    agent = agent!(project, user, "main")

    {:ok, resource, :policy_auto} =
      Core.request_resource(project, agent, %{"name" => "db", "kind" => "database",
                                              "protocol" => "postgres",
                                              "image" => "nvcr.io/nvidia/base/ubuntu:24.04"})

    {:ok, connection, :auto} = Core.connect(agent, resource, "ignored")
    assert connection.state == :active and connection.protocol == "postgres"
  end

  test "same-owner agent to agent auto-approves as a2a" do
    project = project!()
    user = bootstrap_user!(project)
    a = agent!(project, user, "main")
    b = agent!(project, user, "helper")

    {:ok, connection, :auto} = Core.connect(a, b, "anything")
    assert connection.state == :active and connection.protocol == "a2a"
  end

  test "cross-user agent to agent queues for the destination owner" do
    project = project!()
    user1 = bootstrap_user!(project)
    {:ok, user2} = Core.add_user(project, %{"forge_login" => "other", "approved_by_user_id" => user1.id})
    a = agent!(project, user1, "main")
    b = agent!(project, user2, "other-main")

    {:ok, approval, :queued} = Core.connect(a, b, "a2a")
    assert approval.kind == :connect_agents and approval.status == :pending

    # Wrong decider is rejected.
    {:error, _} = Core.decide_approval(approval, user1, :approved)

    {:ok, %{connection: connection}} = Core.decide_approval(approval, user2, :approved)
    assert connection.state == :active and connection.approved_by_user_id == user2.id

    # Second decision on the same approval is rejected.
    {:error, changeset} = Core.decide_approval(approval, user2, :approved)
    assert "has already been decided (approved)" in errors_on(changeset)
  end

  test "denial records without side effects" do
    project = project!()
    user1 = bootstrap_user!(project)
    {:ok, user2} = Core.add_user(project, %{"forge_login" => "other", "approved_by_user_id" => user1.id})
    a = agent!(project, user1, "main")
    b = agent!(project, user2, "other-main")

    {:ok, approval, :queued} = Core.connect(a, b, "a2a")
    {:ok, %{approval: denied}} = Core.decide_approval(approval, user2, :denied)
    assert denied.status == :denied and denied.decided_by_user_id == user2.id

    connection = Mycelium.Core.Repo.get!(Connection, approval.payload["connection_id"])
    assert connection.state == :requested
  end

  # Connection lifecycle -------------------------------------------------------

  test "set_connection_state moves active to revoked; non-active is rejected" do
    project = project!()
    user = bootstrap_user!(project)
    a = agent!(project, user, "main")
    b = agent!(project, user, "helper")
    {:ok, connection, :auto} = Core.connect(a, b, "a2a")

    {:ok, revoked} = Core.set_connection_state(connection, :revoked)
    assert revoked.state == :revoked

    {:error, _} = Core.set_connection_state(revoked, :closed)
  end

  # Sandbox state cache ---------------------------------------------------------

  test "record_sandbox_state caches gateway state with observation time" do
    policy = %{"image_allowlist" => ["nvcr.io/nvidia/base/ubuntu:24.04"]}
    project = project!(policy)
    user = bootstrap_user!(project)
    agent = agent!(project, user, "main")

    {:ok, resource, :policy_auto} =
      Core.request_resource(project, agent, %{"name" => "db", "kind" => "database",
                                              "protocol" => "postgres",
                                              "image" => "nvcr.io/nvidia/base/ubuntu:24.04"})

    sandbox =
      Mycelium.Core.Repo.get_by!(Mycelium.Core.Sandbox, subject_type: :resource, subject_id: resource.id)

    now = DateTime.utc_now()
    {:ok, cached} = Core.record_sandbox_state(sandbox, %{"phase" => "RUNNING"}, now)
    assert cached.gateway_state == %{"phase" => "RUNNING"}
    assert cached.state_cached_at == DateTime.truncate(now, :second)
  end

  # Gateway bindings and tailcat custody ---------------------------------------

  test "bind_sandbox_gateway records the gateway name; custody round-trips" do
    policy = %{"image_allowlist" => ["nvcr.io/nvidia/base/ubuntu:24.04"]}
    project = project!(policy)
    user = bootstrap_user!(project)
    agent = agent!(project, user, "main")

    {:ok, resource, :policy_auto} =
      Core.request_resource(project, agent, %{"name" => "db", "kind" => "database",
                                              "protocol" => "postgres",
                                              "image" => "nvcr.io/nvidia/base/ubuntu:24.04"})

    sandbox =
      Mycelium.Core.Repo.get_by!(Mycelium.Core.Sandbox, subject_type: :resource, subject_id: resource.id)

    {:ok, bound} = Core.bind_sandbox_gateway(sandbox, "gw-sbx-123")
    assert bound.gateway_sandbox_name == "gw-sbx-123"

    {:ok, connection, :auto} = Core.connect(agent, resource, "postgres")

    {:ok, with_custody} =
      Core.set_connection_custody(connection, %{"destination_address" => "tcABC"})

    assert with_custody.tailcat == %{"destination_address" => "tcABC"}

    {:ok, cleared} = Core.set_connection_custody(connection, %{})
    assert cleared.tailcat == %{}
  end

  defp errors_on(changeset), do: for({_field, {msg, _}} <- changeset.errors, do: msg)
end
