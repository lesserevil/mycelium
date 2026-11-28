# Service tests: the gateway is a fake stub behind the Openshell client's
# stub override; the endpoint is exercised through Plug.Test without a
# listener; the domain is real Postgres.
defmodule Openshell.FakeGatewayStub do
  @moduledoc false
  @responses_key :__service_fake_responses__

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

defmodule Mycelium.ServiceTest do
  use ExUnit.Case, async: true

  import Ecto.Adapters.SQL.Sandbox, only: [start_owner!: 2, stop_owner: 1]
  import Plug.Conn, only: [put_req_header: 3]
  import Plug.Test

  alias Mycelium.Core
  alias Mycelium.Core.Repo
  alias Mycelium.Service
  alias Mycelium.Service.Endpoint

  @image "nvcr.io/nvidia/base/ubuntu:24.04"
  @responses_key :__service_fake_responses__
  @stub_key :__openshell_client_stub_override__

  setup do
    owner = start_owner!(Repo, shared: false)
    on_exit(fn -> stop_owner(owner) end)
    Application.put_env(:mycelium_service, :bearer_token, nil)
    :ok
  end

  defp project! do
    {:ok, project} =
      Core.create_project(%{
        "name" => "proj-#{System.unique_integer([:positive])}",
        "repo_url" => "https://github.com/lesserevil/mycelium",
        "default_branch" => "main",
        "policy" => %{"image_allowlist" => [@image]}
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

  defp fake_client(responses) do
    Process.put(@stub_key, Openshell.FakeGatewayStub)
    Process.put(@responses_key, responses)
    {:ok, client} = Openshell.Client.connect([address: "fake:1", tls: false], 5000)
    client
  end

  defp gateway_record(name, phase) do
    %{"sandbox" => %{"metadata" => %{"name" => name}, "status" => %{"phase" => phase}}}
  end

  defp request(method, path, body, opts \\ []) do
    conn =
      conn(method, path, body)
      |> put_req_header("content-type", "application/json")
      |> maybe_auth(opts)
      |> Endpoint.call(Endpoint.init([]))

    # Halted responses (401) carry no body.
    {conn.status, Jason.decode!(conn.resp_body || "{}")}
  end

  defp maybe_auth(conn, opts) do
    case Keyword.get(opts, :token) do
      nil -> conn
      token -> put_req_header(conn, "authorization", "Bearer " <> token)
    end
  end

  # Endpoint: check-in ---------------------------------------------------------

  test "check-in resolves by gateway name and delegates" do
    project = project!()
    user = bootstrap_user!(project)
    source = agent!(project, user, "main")

    {:ok, resource, :policy_auto} =
      Core.request_resource(project, source, %{"name" => "db", "kind" => "database",
                                               "protocol" => "postgres", "image" => @image})

    {:ok, connection, :auto} = Core.connect(source, resource, "postgres")

    # The check-in comes from the connection's destination sandbox.
    destination_sandbox =
      Repo.get_by!(Mycelium.Core.Sandbox, subject_type: :resource, subject_id: resource.id)

    {:ok, _} = Core.bind_sandbox_gateway(destination_sandbox, "gw-svc-1", @image)

    {200, %{"ok" => true}} =
      request(:post, "/mycelium/v1/checkin", %{
        "sandbox" => "gw-svc-1",
        "role" => "serve",
        "connection" => connection.id,
        "address" => "tcABC"
      })

    reloaded = Repo.reload!(destination_sandbox)
    refute is_nil(reloaded.gateway_sandbox_name)

    reloaded_connection = Repo.reload!(connection)
    assert reloaded_connection.tailcat == %{"destination_address" => "tcABC"}
  end

  test "check-in refuses unknown sandboxes with 404" do
    {404, %{"error" => %{"code" => "unknown_sandbox"}}} =
      request(:post, "/mycelium/v1/checkin", %{
        "sandbox" => "nope",
        "role" => "serve",
        "connection" => 1,
        "address" => "tcABC"
      })
  end

  test "check-in refuses malformed payloads with 400" do
    {400, %{"error" => %{"code" => "malformed"}}} =
      request(:post, "/mycelium/v1/checkin", %{"sandbox" => nil})
  end

  test "bearer token is enforced when configured" do
    Application.put_env(:mycelium_service, :bearer_token, "sekrit")

    {401, %{"error" => %{"code" => "unauthorized"}}} =
      request(:post, "/mycelium/v1/poll", %{"sandbox" => "gw-x"})

    {404, _} =
      request(:post, "/mycelium/v1/poll", %{"sandbox" => "gw-x"}, token: "sekrit")
  end

  # Endpoint: poll -------------------------------------------------------------

  test "poll returns desired assignments as JSON" do
    project = project!()
    user = bootstrap_user!(project)
    source = agent!(project, user, "main")

    {:ok, source_sandbox} = Core.create_sandbox(:agent, source.id, %{"image" => @image})
    {:ok, bound} = Core.bind_sandbox_gateway(source_sandbox, "gw-svc-2", @image)

    {:ok, resource, :policy_auto} =
      Core.request_resource(project, source, %{"name" => "db", "kind" => "database",
                                               "protocol" => "postgres", "image" => @image})

    {:ok, connection, :auto} = Core.connect(source, resource, "postgres")

    # The source's poll: destination has no custody yet -> no dial assignment.
    {200, %{"assignments" => []}} =
      request(:post, "/mycelium/v1/poll", %{"sandbox" => "gw-svc-2"})

    # Check in the destination; now the source sees a dial assignment.
    destination_sandbox = Repo.get_by!(Mycelium.Core.Sandbox, subject_type: :resource, subject_id: resource.id)
    {:ok, _} = Core.bind_sandbox_gateway(destination_sandbox, "gw-svc-2-dest", @image)

    {200, %{"ok" => true}} =
      request(:post, "/mycelium/v1/checkin", %{
        "sandbox" => "gw-svc-2-dest",
        "role" => "serve",
        "connection" => connection.id,
        "address" => "tcXYZ"
      })

    {200, %{"assignments" => [%{"role" => "dial", "connection" => id, "address" => "tcXYZ"}]}} =
      request(:post, "/mycelium/v1/poll", %{"sandbox" => "gw-svc-2"})

    assert id == connection.id

    # Unknown sandbox polls 404.
    {404, %{"error" => %{"code" => "unknown_sandbox"}}} =
      request(:post, "/mycelium/v1/poll", %{"sandbox" => "gw-nope"})
  end

  # Agent provisioning -----------------------------------------------------------

  test "provision_agent_sandbox creates the row and binds in one call" do
    project = project!()
    user = bootstrap_user!(project)
    agent = agent!(project, user, "main")

    client =
      fake_client(%{
        create_sandbox: gateway_record("gw-prov-1", "SANDBOX_PHASE_PENDING"),
        get_sandbox: gateway_record("gw-prov-1", "SANDBOX_PHASE_RUNNING")
      })

    {:ok, sandbox} = Service.provision_agent_sandbox(client, agent, @image)
    assert sandbox.gateway_sandbox_name == "gw-prov-1"
    assert sandbox.gateway_state == %{"phase" => "SANDBOX_PHASE_RUNNING"}

    # Second provisioning is refused (409), no gateway call.
    client = fake_client(%{})
    assert {:error, {409, "already_provisioned", _}} =
             Service.provision_agent_sandbox(client, agent, @image)
  end

  test "provision_agent_sandbox refuses unknown agents with 404" do
    client = fake_client(%{})
    assert {:error, {404, "unknown_agent", _}} = Service.provision_agent_sandbox(client, 987_654, @image)
  end
end
