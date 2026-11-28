defmodule Mycelium.Orchestration do
  @moduledoc """
  Binds core domain rows to real OpenShell sandboxes and brokers tailcat
  connections between them.

  Gateway calls go through the `Openshell` client capability; domain mutations
  go through the `Mycelium.Core` context. This module never writes domain
  tables directly and hosts no endpoint: the service component exposes the
  supervisor check-in/poll HTTP surface and calls `register_check_in/4` and
  `pending_assignments/1` here.

  The supervisor protocol (component.md): check-ins carry
  `{"sandbox", "role" => "serve", "connection", "address"}`; polls return the
  full desired assignment state, which the supervisor reconciles.
  """

  import Ecto.Query

  alias Mycelium.Core
  alias Mycelium.Core.Agent
  alias Mycelium.Core.Connection
  alias Mycelium.Core.Repo
  alias Mycelium.Core.Resource
  alias Mycelium.Core.Sandbox

  # The gateway workspace every project's sandboxes live in for 0.1.
  @gateway_workspace "default"

  # The main process every allowlisted image runs (component.md contract).
  @supervisor_command ["/usr/local/bin/mycelium-supervisor"]

  @custody_key "destination_address"

  # -- Sandbox provisioning ---------------------------------------------------

  @doc """
  Binds a domain sandbox row to a real gateway sandbox: refuses images
  outside the project's allowlist, creates the gateway sandbox exactly once
  for an unbound row, records the gateway sandbox name, and refreshes the
  cached state. Idempotent for an already-bound row.
  """
  @spec ensure_sandbox(Openshell.Client.t(), Sandbox.t() | integer()) ::
          {:ok, Sandbox.t()} | {:error, term()}
  def ensure_sandbox(client, sandbox) do
    with {:ok, sandbox} <- resolve_sandbox(sandbox) do
      case bound_name(sandbox) do
        nil -> create_gateway_sandbox(client, sandbox)
        _name -> refresh_sandbox_state(client, sandbox)
      end
    end
  end

  defp create_gateway_sandbox(client, sandbox) do
    with {:ok, project} <- subject_project(sandbox),
         :ok <- allowlisted?(project, sandbox.image),
         {:ok, gateway_sandbox} <-
           Openshell.Sandboxes.create(client, @gateway_workspace, %{
             image: sandbox.image,
             command: @supervisor_command
           }, 30_000),
         name when is_binary(name) and name != "" <- gateway_sandbox_name(gateway_sandbox) do
      with {:ok, sandbox} <- Core.bind_sandbox_gateway(sandbox, name, sandbox.image) do
        refresh_sandbox_state(client, sandbox)
      end
    end
  end

  defp allowlisted?(project, image) when is_binary(image) and image != "" do
    allowlist = (project.policy && project.policy["image_allowlist"]) || []

    if image in allowlist do
      :ok
    else
      {:error, "image #{inspect(image)} is not in the project's image_allowlist"}
    end
  end

  defp allowlisted?(_project, image),
    do: {:error, "sandbox has no image to provision (got #{inspect(image)})"}

  # -- Cached gateway state ---------------------------------------------------

  @doc "Reads the sandbox from the gateway and caches the observation."
  @spec refresh_sandbox_state(Openshell.Client.t(), Sandbox.t() | integer()) ::
          {:ok, Sandbox.t()} | {:error, term()}
  def refresh_sandbox_state(client, sandbox) do
    with {:ok, sandbox} <- resolve_sandbox(sandbox),
         name when is_binary(name) and name != "" <- bound_name(sandbox),
         {:ok, gateway_sandbox} <-
           Openshell.Sandboxes.get(client, @gateway_workspace, name) do
      Core.record_sandbox_state(sandbox, cached_state(gateway_sandbox), DateTime.utc_now())
    end
  end

  # -- Connection brokerage ---------------------------------------------------

  @doc "Validates that an approved connection may run its tailcat handshake."
  @spec open_connection(Openshell.Client.t(), Connection.t() | integer()) ::
          {:ok, Connection.t()} | {:error, term()}
  def open_connection(_client, connection) do
    with {:ok, connection} <- resolve_connection(connection),
         :ok <- active?(connection) do
      # The handshake itself is driven by polls and check-ins; the desired
      # state is computed from the domain rows.
      {:ok, connection}
    end
  end

  @doc "Clears a connection's tailcat custody; assignments disappear from polls."
  @spec close_connection(Openshell.Client.t(), Connection.t() | integer()) ::
          {:ok, Connection.t()} | {:error, term()}
  def close_connection(_client, connection) do
    with {:ok, connection} <- resolve_connection(connection) do
      Core.set_connection_custody(connection, %{})
    end
  end

  @doc """
  Records a supervisor check-in. Idempotent for identical input; refuses
  unknown or unbound sandboxes. `opts[:connection]` names the connection the
  listener serves.
  """
  @spec register_check_in(Sandbox.t() | integer(), :serve | String.t(), String.t(), keyword()) ::
          {:ok, Connection.t()} | {:error, term()}
  def register_check_in(sandbox, role, address, opts) do
    with {:ok, sandbox} <- resolve_sandbox(sandbox),
         :ok <- serve_role?(role),
         true <- is_binary(address) and address != "",
         connection_id when is_integer(connection_id) <- opts[:connection],
         {:ok, connection} <- fetch_connection(connection_id),
         :ok <- active?(connection),
         :ok <- serves_subject?(connection, sandbox),
         {:ok, _sandbox} <- Core.bind_sandbox_gateway(sandbox, bound_name(sandbox)) do
      Core.set_connection_custody(connection, %{@custody_key => address})
    end
  end

  defp serve_role?(:serve), do: :ok
  defp serve_role?("serve"), do: :ok
  defp serve_role?(other), do: {:error, "check-in role must be serve, got #{inspect(other)}"}

  defp serves_subject?(%Connection{destination_type: type, destination_id: id}, %Sandbox{
         subject_type: type,
         subject_id: id
       }),
       do: :ok

  defp serves_subject?(_connection, _sandbox),
    do: {:error, "sandbox does not serve this connection's destination"}

  @doc """
  Returns the full desired assignment state for a sandbox: `serve` for each
  active connection this sandbox is the destination of that has no custody
  address yet, and `dial` for each active connection this sandbox is the
  source of whose destination address is known.
  """
  @spec pending_assignments(Sandbox.t() | integer()) ::
          {:ok, [map()]} | {:error, term()}
  def pending_assignments(sandbox) do
    with {:ok, sandbox} <- resolve_sandbox(sandbox) do
      assignments =
        Connection
        |> where([c], c.state == :active)
        |> Repo.all()
        |> Enum.flat_map(&assignments_for(&1, sandbox))

      {:ok, assignments}
    end
  end

  defp assignments_for(
         %Connection{
           id: id,
           source_agent_id: source_id,
           destination_type: type,
           destination_id: dest_id,
           tailcat: tailcat
         },
         %Sandbox{subject_type: st, subject_id: sid}
       ) do
    serves? = st == type and sid == dest_id
    sources? = st == :agent and sid == source_id
    address = custody_address(tailcat)

    cond do
      serves? and is_nil(address) -> [%{"role" => "serve", "connection" => id}]
      sources? and is_binary(address) -> [%{"role" => "dial", "connection" => id, "address" => address}]
      true -> []
    end
  end

  defp custody_address(tailcat) when is_map(tailcat), do: tailcat[@custody_key]
  defp custody_address(_), do: nil

  # -- Sandbox deletion ---------------------------------------------------------

  @doc """
  Deletes the gateway sandbox and clears the domain binding; refuses while an
  active connection references the subject.
  """
  @spec delete_sandbox(Openshell.Client.t(), Sandbox.t() | integer()) ::
          :ok | {:error, term()}
  def delete_sandbox(client, sandbox) do
    with {:ok, sandbox} <- resolve_sandbox(sandbox),
         name when is_binary(name) and name != "" <- bound_name(sandbox),
         [] <- active_connections_for(sandbox) do
      with {:ok, :deleted} <- Openshell.Sandboxes.delete(client, @gateway_workspace, name),
           {:ok, _sandbox} <- Core.bind_sandbox_gateway(sandbox, nil) do
        :ok
      end
    else
      nil -> {:error, "sandbox is not bound to a gateway sandbox"}
      [%Connection{id: id} | _rest] ->
        {:error, "sandbox still has active connection #{id}"}

      error ->
        error
    end
  end

  defp active_connections_for(%Sandbox{subject_type: :agent, subject_id: sid}) do
    Connection
    |> where(
      [c],
      c.state == :active and
        ((c.destination_type == :agent and c.destination_id == ^sid) or
           c.source_agent_id == ^sid)
    )
    |> Repo.all()
  end

  defp active_connections_for(%Sandbox{subject_type: :resource, subject_id: sid}) do
    Connection
    |> where(
      [c],
      c.state == :active and c.destination_type == :resource and c.destination_id == ^sid
    )
    |> Repo.all()
  end

  # -- Internals ----------------------------------------------------------------

  # Re-read structs from the DB: a struct carried in memory may not exist or
  # may be stale, and trust/binding decisions must see current state.
  defp resolve_sandbox(%Sandbox{} = sandbox), do: resolve_sandbox(sandbox.id)
  defp resolve_sandbox(id) when is_integer(id), do: fetch(Repo.get(Sandbox, id), :sandbox)
  defp resolve_sandbox(_), do: {:error, "sandbox is unknown"}

  defp resolve_connection(%Connection{} = connection), do: resolve_connection(connection.id)

  defp resolve_connection(id) when is_integer(id),
    do: fetch(Repo.get(Connection, id), :connection)

  defp resolve_connection(_), do: {:error, "connection is unknown"}

  defp fetch_connection(id) when is_integer(id), do: fetch(Repo.get(Connection, id), :connection)
  defp fetch_connection(_), do: {:error, "connection is unknown"}

  defp fetch(nil, :sandbox), do: {:error, "sandbox is unknown"}
  defp fetch(nil, :connection), do: {:error, "connection is unknown"}
  defp fetch(record, _), do: {:ok, record}

  defp active?(%Connection{state: :active}), do: :ok
  defp active?(%Connection{state: other}), do: {:error, "connection is not active (#{other})"}

  defp bound_name(%Sandbox{gateway_sandbox_name: name}), do: name

  defp subject_project(%Sandbox{subject_type: type, subject_id: id}) do
    case Repo.get(subject_module(type), id) do
      nil -> {:error, "sandbox subject is unknown"}
      subject -> fetch(Repo.get(Mycelium.Core.Project, subject.project_id), :project)
    end
  end

  defp subject_module(:agent), do: Agent
  defp subject_module(:resource), do: Resource
  defp subject_module(_), do: Resource

  # Gateway records arrive as protobuf structs from the live gateway and as
  # plain maps from test fakes; extract defensively.

  defp gateway_sandbox_name(response) do
    case field(response, :metadata) do
      nil -> {:error, "gateway sandbox response has no metadata"}
      metadata -> field(metadata, :name) || {:error, "gateway sandbox response has no name"}
    end
  end

  defp cached_state(response) do
    status = field(response, :status) || %{}
    %{"phase" => field(status, :phase)}
  end

  defp field(struct_or_map, key) when is_struct(struct_or_map) do
    if Map.has_key?(struct_or_map, key), do: Map.get(struct_or_map, key)
  end

  defp field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
