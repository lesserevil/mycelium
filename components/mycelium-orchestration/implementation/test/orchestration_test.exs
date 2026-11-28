# Hermetic orchestration tests: the gateway is an in-test fake stub behind the
# Openshell client's stub override; the domain is real Postgres.
defmodule Openshell.FakeGatewayStub do
  @moduledoc false
  @responses_key :__orchestration_fake_responses__

  def connect(_address, _opts), do: {:ok, :fake_channel}
  def disconnect(:fake_channel), do: :ok

  def health(_channel, _request, _opts), do: respond(:health)
  def list_sandboxes(_channel, _request, _opts), do: respond(:list_sandboxes)
  def get_sandbox(_channel, _request, _opts), do: respond(:get_sandbox)
  def create_sandbox(_channel, _request, _opts), do: respond(:create_sandbox)
  def delete_sandbox(_channel, _request, _opts), do: respond(:delete_sandbox)

  defp respond(method) do
    case Process.get(@responses_key) do
      responses when is_map(responses) ->
        case Map.fetch(responses, method) do
          {:ok, value} -> if is_tuple(value), do: value, else: {:ok, value}
          :error -> raise ArgumentError, "no fake gateway response configured for #{inspect(method)}"
        end

      _ ->
        raise ArgumentError, "no fake gateway responses configured"
    end
  end
end

defmodule Mycelium.OrchestrationTest do
  use ExUnit.Case, async: true

  import Ecto.Adapters.SQL.Sandbox, only: [start_owner!: 2, stop_owner: 1]

  alias Mycelium.Core
  alias Mycelium.Core.Repo
  alias Mycelium.Orchestration

  @image "nvcr.io/nvidia/base/ubuntu:24.04"
  @responses_key :__orchestration_fake_responses__
  @stub_key :__openshell_client_stub_override__

  setup do
    owner = start_owner!(Repo, shared: false)
    on_exit(fn -> stop_owner(owner) end)
    :ok
  end

  defp project!(policy \\ %{"image_allowlist" => [@image]}) do
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

  defp resource_sandbox!(project, agent, name, image \\ @image) do
    {:ok, resource, :policy_auto} =
      Core.request_resource(project, agent, %{
        "name" => name,
        "kind" => "database",
        "protocol" => "postgres",
        "image" => image
      })

    Repo.get_by!(Mycelium.Core.Sandbox, subject_type: :resource, subject_id: resource.id)
  end

  defp agent_sandbox!(project, agent) do
    {:ok, sandbox} =
      %Mycelium.Core.Sandbox{}
      |> Mycelium.Core.Sandbox.changeset(%{
        subject_type: :agent,
        subject_id: agent.id,
        image: @image
      })
      |> Repo.insert()

    sandbox
  end

  defp fake_client(responses) do
    Process.put(@stub_key, Openshell.FakeGatewayStub)
    Process.put(@responses_key, responses)
    {:ok, client} = Openshell.Client.connect([address: "fake:1", tls: false], 5000)
    client
  end

  defp gateway_record(name, phase) do
    %{"sandbox" => %{"metadata" => %{"name" => name}, "status" => %{"phase" => phase}}}
  end

  # ensure_sandbox -------------------------------------------------------------

  test "ensure_sandbox refuses unallowlisted images before any gateway call" do
    project = project!(%{"image_allowlist" => [@image]})
    user = bootstrap_user!(project)
    agent = agent!(project, user, "main")

    # Resource rows are policy-gated, so an unallowlisted image can only reach
    # a sandbox row directly (agent rows, or a policy narrowed after the fact).
    {:ok, sandbox} =
      %Mycelium.Core.Sandbox{}
      |> Mycelium.Core.Sandbox.changeset(%{
        subject_type: :agent,
        subject_id: agent.id,
        image: "other/image"
      })
      |> Repo.insert()

    # No create response configured: a gateway call would raise.
    client = fake_client(%{})

    assert {:error, message} = Orchestration.ensure_sandbox(client, sandbox)
    assert message =~ "other/image"
  end

  test "ensure_sandbox creates the gateway sandbox once, binds and refreshes" do
    project = project!()
    user = bootstrap_user!(project)
    agent = agent!(project, user, "main")
    sandbox = resource_sandbox!(project, agent, "db")

    responses = %{
      create_sandbox: gateway_record("gw-sbx-1", "SANDBOX_PHASE_PENDING"),
      get_sandbox: gateway_record("gw-sbx-1", "SANDBOX_PHASE_RUNNING")
    }

    client = fake_client(responses)

    {:ok, bound} = Orchestration.ensure_sandbox(client, sandbox)
    assert bound.gateway_sandbox_name == "gw-sbx-1"
    assert bound.gateway_state == %{"phase" => "SANDBOX_PHASE_RUNNING"}

    # Idempotent: a bound row only refreshes (create would raise unconfigured).
    client = fake_client(%{get_sandbox: gateway_record("gw-sbx-1", "SANDBOX_PHASE_RUNNING")})
    {:ok, refreshed} = Orchestration.ensure_sandbox(client, bound)
    assert refreshed.gateway_sandbox_name == "gw-sbx-1"
  end

  test "ensure_sandbox refuses subjects with no image" do
    project = project!()
    user = bootstrap_user!(project)
    agent = agent!(project, user, "main")

    {:ok, sandbox} =
      %Mycelium.Core.Sandbox{}
      |> Mycelium.Core.Sandbox.changeset(%{subject_type: :agent, subject_id: agent.id})
      |> Repo.insert()

    client = fake_client(%{})
    assert {:error, message} = Orchestration.ensure_sandbox(client, sandbox)
    assert message =~ "no image"
  end

  # Connection handshake -------------------------------------------------------

  test "check-in and polls drive the two-sided handshake" do
    project = project!()
    user = bootstrap_user!(project)
    source = agent!(project, user, "main")
    source_sandbox = agent_sandbox!(project, source)
    destination_sandbox = resource_sandbox!(project, source, "db")

    client = fake_client(%{})
    {:ok, connection, :auto} = Core.connect(source, Core.Repo.get!(Mycelium.Core.Resource, destination_sandbox.subject_id), "postgres")
    {:ok, _} = Orchestration.open_connection(client, connection)

    # Destination polls: sees a serve assignment.
    {:ok, [%{"role" => "serve", "connection" => id}]} =
      Orchestration.pending_assignments(destination_sandbox)

    assert id == connection.id

    # Unbound or wrong-role check-ins are refused.
    assert {:error, message} =
             Orchestration.register_check_in(destination_sandbox, :dial, "tcABC", connection: connection.id)

    assert message =~ "serve"

    assert {:error, message} =
             Orchestration.register_check_in(%Mycelium.Core.Sandbox{id: destination_sandbox.id + 999_999,
                                                                    subject_type: :resource,
                                                                    subject_id: destination_sandbox.subject_id},
               :serve, "tcABC", connection: connection.id)

    assert message =~ "unknown"

    # The destination checks in its listener address.
    {:ok, with_custody} =
      Orchestration.register_check_in(destination_sandbox, :serve, "tcABC", connection: connection.id)

    assert with_custody.tailcat == %{"destination_address" => "tcABC"}

    # Idempotent duplicate check-in.
    {:ok, again} =
      Orchestration.register_check_in(destination_sandbox, :serve, "tcABC", connection: connection.id)

    assert again.tailcat == %{"destination_address" => "tcABC"}

    # Destination's serve assignment is satisfied; source sees the dial.
    {:ok, []} = Orchestration.pending_assignments(destination_sandbox)

    {:ok, [%{"role" => "dial", "connection" => id, "address" => "tcABC"}]} =
      Orchestration.pending_assignments(source_sandbox)

    assert id == connection.id
  end

  test "open_connection refuses non-active connections" do
    project = project!()
    user1 = bootstrap_user!(project)
    {:ok, user2} = Core.add_user(project, %{"forge_login" => "other", "approved_by_user_id" => user1.id})
    a = agent!(project, user1, "main")
    b = agent!(project, user2, "other")

    {:ok, approval, :queued} = Core.connect(a, b, "a2a")
    connection = Repo.get!(Mycelium.Core.Connection, approval.payload["connection_id"])

    client = fake_client(%{})
    assert {:error, message} = Orchestration.open_connection(client, connection)
    assert message =~ "not active"
  end

  test "close_connection clears custody; polls stop serving the connection" do
    project = project!()
    user = bootstrap_user!(project)
    source = agent!(project, user, "main")
    source_sandbox = agent_sandbox!(project, source)
    destination_sandbox = resource_sandbox!(project, source, "db")

    client = fake_client(%{})
    {:ok, connection, :auto} = Core.connect(source, Repo.get!(Mycelium.Core.Resource, destination_sandbox.subject_id), "postgres")

    {:ok, _} =
      Orchestration.register_check_in(destination_sandbox, :serve, "tcXYZ", connection: connection.id)

    {:ok, _} = Orchestration.close_connection(client, connection)
    cleared = Repo.reload(connection)
    assert cleared.tailcat == %{}

    {:ok, [%{"role" => "serve", "connection" => id}]} =
      Orchestration.pending_assignments(destination_sandbox)

    assert id == connection.id
  end

  # Sandbox deletion -----------------------------------------------------------

  test "delete_sandbox refuses while connected, otherwise deletes and unbinds" do
    project = project!()
    user = bootstrap_user!(project)
    source = agent!(project, user, "main")
    source_sandbox = agent_sandbox!(project, source)

    responses = %{
      create_sandbox: gateway_record("gw-sbx-9", "SANDBOX_PHASE_PENDING"),
      get_sandbox: gateway_record("gw-sbx-9", "SANDBOX_PHASE_RUNNING"),
      delete_sandbox: %{}
    }

    client = fake_client(responses)
    {:ok, destination_sandbox} = Orchestration.ensure_sandbox(client, resource_sandbox!(project, source, "db"))

    {:ok, connection, :auto} = Core.connect(source, Repo.get!(Mycelium.Core.Resource, destination_sandbox.subject_id), "postgres")

    assert {:error, message} = Orchestration.delete_sandbox(client, destination_sandbox)
    assert message =~ "active connection"

    {:ok, _} = Core.set_connection_state(connection, :revoked)
    :ok = Orchestration.delete_sandbox(client, destination_sandbox)
    reloaded = Repo.reload!(destination_sandbox)
    assert is_nil(reloaded.gateway_sandbox_name)
  end
end
