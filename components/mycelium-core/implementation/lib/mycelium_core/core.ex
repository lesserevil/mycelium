defmodule Mycelium.Core do
  @moduledoc """
  Context module for the Mycelium core domain. Every mutation goes through
  this module so the trust rules and project policy evaluation are applied
  exactly once. Consumers shall not insert into the schema tables directly.

  Trust rules (component.md):

  - Agents are implicitly trusted once added by an approved user.
  - Connections: agent→resource and same-owner agent→agent auto-approve;
    cross-user agent→agent queues an approval for the destination owner.
  - Resource requests: within project policy auto-create; beyond, queue.
  - The approval queue applies each decision exactly once.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias Mycelium.Core.Agent
  alias Mycelium.Core.Approval
  alias Mycelium.Core.Connection
  alias Mycelium.Core.Credential
  alias Mycelium.Core.Project
  alias Mycelium.Core.Repo
  alias Mycelium.Core.Resource
  alias Mycelium.Core.Sandbox
  alias Mycelium.Core.User

  @typedoc "A record struct or its primary key."
  @type ref :: struct() | integer()

  # -- Projects -------------------------------------------------------------

  @spec create_project(map()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def create_project(attrs) when is_map(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  # -- Users ----------------------------------------------------------------

  @spec add_user(Project.t() | integer(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def add_user(project, attrs) when is_map(attrs) do
    with {:ok, project} <- resolve_project(project) do
      if Repo.aggregate(from(u in User, where: u.project_id == ^project.id), :count) == 0 do
        # Bootstrap: the first user of an empty project is self-approved.
        {:ok, user} =
          %User{}
          |> User.changeset(
            Map.merge(stringify_keys(attrs), %{"project_id" => project.id, "approved" => true})
          )
          |> put_change(:approved_by_user_id, nil)
          |> Repo.insert()

        user
        |> change()
        |> put_change(:approved_by_user_id, user.id)
        |> Repo.update()
      else
        approver_id = attrs[:approved_by_user_id] || attrs["approved_by_user_id"]

        case owner_of_project?(approver_id, project.id) do
          true ->
            %User{}
            |> User.changeset(
              Map.merge(stringify_keys(attrs), %{"project_id" => project.id, "approved" => true})
            )
            |> Repo.insert()

          false ->
            error_changeset(%User{}, :approved_by_user_id,
              "must reference an approved user of the project"
            )
        end
      end
    end
  end

  @spec add_credential(User.t() | integer(), map()) ::
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def add_credential(user, attrs) when is_map(attrs) do
    with {:ok, user} <- resolve_user(user) do
      %Credential{}
      |> Credential.changeset(Map.put(stringify_keys(attrs), "user_id", user.id))
      |> Repo.insert()
    end
  end

  # -- Agents ---------------------------------------------------------------

  @spec add_agent(Project.t() | integer(), User.t() | integer(), map()) ::
          {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def add_agent(project, owner, attrs) when is_map(attrs) do
    with {:ok, project} <- resolve_project(project),
         {:ok, owner} <- resolve_user(owner),
         true <- owner_of_project?(owner, project.id) do
      attrs =
        attrs
        |> stringify_keys()
        |> Map.put("project_id", project.id)
        |> Map.put("owner_user_id", owner.id)
        |> Map.put("added_by_user_id", owner.id)

      %Agent{}
      |> Agent.changeset(attrs)
      |> Repo.insert()
    else
      {:error, _} = error -> error
      false -> error_changeset(%Agent{}, :owner_user_id, "must be an approved user of the project")
    end
  end

  # -- Resources ------------------------------------------------------------

  @spec request_resource(Project.t() | integer(), Agent.t() | integer(), map()) ::
          {:ok, Resource.t(), :policy_auto}
          | {:ok, Approval.t(), :queued}
          | {:error, Ecto.Changeset.t()}
  def request_resource(project, requester_agent, attrs) when is_map(attrs) do
    with {:ok, project} <- resolve_project(project),
         {:ok, agent} <- resolve_agent(requester_agent),
         true <- agent.project_id == project.id,
         true <- owner_approved?(agent.owner_user_id) do
      policy = project.policy || %{}
      limit = policy["resource_count_limit"]
      allowlist = policy["image_allowlist"] || []
      attrs = stringify_keys(attrs)

      count =
        Repo.aggregate(from(r in Resource, where: r.project_id == ^project.id), :count)

      image = attrs["image"]

      if within_limit?(count, limit) and image in allowlist do
        resource = insert_resource(project.id, agent.id, attrs, :policy_auto)
        {:ok, resource, :policy_auto}
      else
        {:ok, approval, :queued} =
          insert_approval(%{
            "project_id" => project.id,
            "kind" => :add_resource,
            "requester_type" => :agent,
            "requester_id" => agent.id,
            "payload" => attrs
          })

        {:ok, approval, :queued}
      end
    else
      {:error, _} = error -> error
      false -> error_changeset(%Resource{}, :agent, "must belong to the project")
    end
  end

  # -- Connections ----------------------------------------------------------

  @spec connect(Agent.t() | integer(), Agent.t() | Resource.t() | map(), String.t()) ::
          {:ok, Connection.t(), :auto}
          | {:ok, Approval.t(), :queued}
          | {:error, Ecto.Changeset.t()}
  def connect(from_agent, to_subject, protocol) do
    with {:ok, agent} <- resolve_agent(from_agent),
         {:ok, destination} <- resolve_destination(to_subject) do
      apply_connection_rules(agent, destination, protocol)
    end
  end

  defp apply_connection_rules(agent, {:agent, destination}, _protocol) do
    if agent.owner_user_id == destination.owner_user_id do
      {:ok, insert_connection(agent, :agent, destination.id, "a2a", :active), :auto}
    else
      connection = insert_connection(agent, :agent, destination.id, "a2a", :requested)

      {:ok, approval, :queued} =
        insert_approval(%{
          "project_id" => agent.project_id,
          "kind" => :connect_agents,
          "requester_type" => :agent,
          "requester_id" => agent.id,
          "payload" => %{
            "connection_id" => connection.id,
            "target_user_id" => destination.owner_user_id
          }
        })

      {:ok, approval, :queued}
    end
  end

  defp apply_connection_rules(agent, {:resource, resource}, _protocol) do
    {:ok, insert_connection(agent, :resource, resource.id, resource.protocol, :active), :auto}
  end

  defp insert_connection(agent, destination_type, destination_id, protocol, state) do
    %Connection{}
    |> Connection.changeset(%{
      project_id: agent.project_id,
      source_agent_id: agent.id,
      destination_type: destination_type,
      destination_id: destination_id,
      protocol: protocol,
      state: state
    })
    |> Repo.insert!()
  end

  # -- Approvals ------------------------------------------------------------

  @spec decide_approval(Approval.t() | integer(), User.t() | integer(), :approved | :denied) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()}
  def decide_approval(approval, decider, decision) when decision in [:approved, :denied] do
    with {:ok, approval} <- resolve_approval(approval),
         {:ok, decider} <- resolve_user(decider),
         :ok <- pending?(approval) do
      apply_decision(approval, decider, decision)
    end
  end

  def decide_approval(_approval, _decider, decision),
    do: error_changeset(%Approval{}, :decision, "must be approved or denied, got #{inspect(decision)}")

  defp pending?(%Approval{status: :pending}), do: :ok

  defp pending?(%Approval{status: other}),
    do: error_changeset(%Approval{}, :status, "has already been decided (#{other})")

  defp apply_decision(approval, decider, :approved) do
    case approval.kind do
      :connect_agents -> apply_connect_approval(approval, decider)
      :add_resource -> apply_resource_approval(approval, decider)
      _ -> record_decision(approval, decider, :approved)
    end
  end

  defp apply_decision(approval, decider, :denied),
    do: record_decision(approval, decider, :denied)

  defp apply_connect_approval(approval, decider) do
    target_user_id = approval.payload["target_user_id"]

    if decider.id == target_user_id do
      connection = Repo.get!(Connection, approval.payload["connection_id"])

      connection =
        connection
        |> change()
        |> put_change(:state, :active)
        |> put_change(:approved_by_user_id, decider.id)
        |> Repo.update!()

      {:ok, %{approval: record_decision!(approval, decider, :approved), connection: connection}}
    else
      error_changeset(%Approval{}, :decided_by_user_id,
        "must be the destination agent's owner"
      )
    end
  end

  defp apply_resource_approval(approval, decider) do
    resource = insert_resource(approval.project_id, approval.requester_id, approval.payload, :approval)

    {:ok, %{approval: record_decision!(approval, decider, :approved), resource: resource}}
  end

  defp record_decision(approval, decider, status) do
    {:ok, %{approval: record_decision!(approval, decider, status)}}
  end

  defp record_decision!(approval, decider, status) do
    # shortcut: check-then-update is not concurrency-safe; add a conditional
    # UPDATE (WHERE status = 'pending') when approvals may be decided concurrently
    approval
    |> change()
    |> put_change(:status, status)
    |> put_change(:decided_by_user_id, decider.id)
    |> put_change(:decided_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update!()
  end

  # -- Connection lifecycle ---------------------------------------------------

  @spec set_connection_state(Connection.t() | integer(), :revoked | :closed, keyword()) ::
          {:ok, Connection.t()} | {:error, Ecto.Changeset.t()}
  def set_connection_state(connection, state, opts \\ [])

  def set_connection_state(connection, state, _opts)
      when state in [:revoked, :closed] do
    with {:ok, connection} <- resolve_connection(connection),
         :ok <- active?(connection) do
      connection
      |> change()
      |> put_change(:state, state)
      |> Repo.update()
    end
  end

  def set_connection_state(_connection, state, _opts),
    do: error_changeset(%Connection{}, :state, "must be revoked or closed, got #{inspect(state)}")

  defp active?(%Connection{state: :active}), do: :ok

  defp active?(%Connection{state: other}),
    do: error_changeset(%Connection{}, :state, "is not active (#{other})")

  # -- Sandbox state cache ----------------------------------------------------

  @spec record_sandbox_state(Sandbox.t() | integer(), map(), DateTime.t()) ::
          {:ok, Sandbox.t()} | {:error, Ecto.Changeset.t()}
  def record_sandbox_state(sandbox, gateway_state, observed_at) do
    with {:ok, sandbox} <- resolve_sandbox(sandbox),
         true <- is_map(gateway_state) and not is_struct(gateway_state),
         %DateTime{} = observed_at <- observed_at do
      sandbox
      |> change()
      |> put_change(:gateway_state, gateway_state)
      |> put_change(:state_cached_at, DateTime.truncate(observed_at, :second))
      |> Repo.update()
    else
      false -> error_changeset(%Sandbox{}, :gateway_state, "must be a map")
      _ -> error_changeset(%Sandbox{}, :state_cached_at, "must be a timestamp")
    end
  end

  # -- Sandbox rows -----------------------------------------------------------

  @doc """
  Creates a sandbox row for an existing agent or resource subject. Refuses
  unknown subjects and a second row for the same subject, so the
  one-runtime-binding invariant holds.
  """
  @spec create_sandbox(:agent | :resource, integer(), map()) ::
          {:ok, Sandbox.t()} | {:error, Ecto.Changeset.t()}
  def create_sandbox(subject_type, subject_id, attrs \\ %{})
      when subject_type in [:agent, :resource] and is_integer(subject_id) do
    subject = Repo.get(subject_module(subject_type), subject_id)
    existing = Repo.get_by(Sandbox, subject_type: subject_type, subject_id: subject_id)

    cond do
      is_nil(subject) ->
        error_changeset(%Sandbox{}, :subject_id, "subject is unknown")

      not is_nil(existing) ->
        error_changeset(%Sandbox{}, :subject_id, "already has a sandbox row")

      true ->
        %Sandbox{}
        |> Sandbox.changeset(Map.merge(stringify_keys(attrs), %{
          "subject_type" => subject_type,
          "subject_id" => subject_id
        }))
        |> Repo.insert()
    end
  end

  defp subject_module(:agent), do: Agent
  defp subject_module(:resource), do: Resource

  # -- Gateway bindings and tailcat custody ---------------------------------

  @spec bind_sandbox_gateway(Sandbox.t() | integer(), String.t(), String.t() | nil) ::
          {:ok, Sandbox.t()} | {:error, Ecto.Changeset.t()}
  def bind_sandbox_gateway(sandbox, gateway_sandbox_name, image \\ nil) do
    with {:ok, sandbox} <- resolve_sandbox(sandbox),
         true <-
           is_nil(gateway_sandbox_name) or
             (is_binary(gateway_sandbox_name) and gateway_sandbox_name != "") do
      sandbox
      |> change()
      |> put_change(:gateway_sandbox_name, gateway_sandbox_name)
      |> put_change(:image, image)
      |> Repo.update()
    else
      false -> error_changeset(%Sandbox{}, :gateway_sandbox_name, "must be a nonempty string")
      error -> error
    end
  end

  @spec set_connection_custody(Connection.t() | integer(), map() | nil) ::
          {:ok, Connection.t()} | {:error, Ecto.Changeset.t()}
  def set_connection_custody(connection, custody) do
    with {:ok, connection} <- resolve_connection(connection),
         true <- is_nil(custody) or (is_map(custody) and not is_struct(custody)) do
      connection
      |> change()
      |> put_change(:tailcat, custody)
      |> Repo.update()
    else
      false -> error_changeset(%Connection{}, :tailcat, "must be a map or nil")
      error -> error
    end
  end

  # -- Internals --------------------------------------------------------------

  defp insert_resource(project_id, agent_id, attrs, created_via) do
    {:ok, resource} =
      %Resource{}
      |> Resource.changeset(%{
        "name" => attrs["name"],
        "kind" => attrs["kind"],
        "protocol" => attrs["protocol"],
        "config" => attrs["config"] || %{},
        "created_via" => created_via,
        "project_id" => project_id,
        "requested_by_agent_id" => agent_id
      })
      |> Repo.insert()

    {:ok, _sandbox} =
      %Sandbox{}
      |> Sandbox.changeset(%{
        subject_type: :resource,
        subject_id: resource.id,
        gateway_sandbox_name: attrs["gateway_sandbox_name"],
        image: attrs["image"]
      })
      |> Repo.insert()

    Repo.get!(Resource, resource.id)
  end

  defp insert_approval(attrs) do
    {:ok, approval} =
      %Approval{}
      |> Approval.changeset(Map.merge(%{"status" => :pending}, stringify_keys(attrs)))
      |> Repo.insert()

    {:ok, approval, :queued}
  end

  defp within_limit?(_count, nil), do: true
  defp within_limit?(count, limit) when is_integer(limit), do: count < limit
  defp within_limit?(_count, _limit), do: false

  # Trust decisions read current DB state; an in-memory struct may be stale.
  defp owner_of_project?(%User{} = user, project_id),
    do: owner_of_project?(user.id, project_id)

  defp owner_of_project?(user_id, project_id) when is_integer(user_id) do
    case Repo.get(User, user_id) do
      %User{approved: true, project_id: ^project_id} -> true
      _ -> false
    end
  end

  defp owner_of_project?(_user_id, _project_id), do: false

  defp owner_approved?(user_id) do
    case Repo.get(User, user_id) do
      %User{approved: true} -> true
      _ -> false
    end
  end


  defp resolve_project(%Project{} = project), do: {:ok, project}
  defp resolve_project(id) when is_integer(id), do: fetch(Repo.get(Project, id), :project)
  defp resolve_project(_), do: error_changeset(%Project{}, :project, "is unknown")

  defp resolve_user(%User{} = user), do: {:ok, user}
  defp resolve_user(id) when is_integer(id), do: fetch(Repo.get(User, id), :user)
  defp resolve_user(_), do: error_changeset(%User{}, :user, "is unknown")

  defp resolve_agent(%Agent{} = agent), do: {:ok, agent}
  defp resolve_agent(id) when is_integer(id), do: fetch(Repo.get(Agent, id), :agent)
  defp resolve_agent(_), do: error_changeset(%Agent{}, :agent, "is unknown")

  # Approval decisions must read current DB state; a struct carried in memory
  # may claim :pending after the same approval was already decided.
  defp resolve_approval(%Approval{} = approval), do: resolve_approval(approval.id)

  defp resolve_approval(id) when is_integer(id),
    do: fetch(Repo.get(Approval, id), :approval)

  defp resolve_approval(_), do: error_changeset(%Approval{}, :approval, "is unknown")

  defp resolve_connection(%Connection{} = connection), do: {:ok, connection}

  defp resolve_connection(id) when is_integer(id),
    do: fetch(Repo.get(Connection, id), :connection)

  defp resolve_connection(_), do: error_changeset(%Connection{}, :connection, "is unknown")

  defp resolve_sandbox(%Sandbox{} = sandbox), do: {:ok, sandbox}

  defp resolve_sandbox(id) when is_integer(id),
    do: fetch(Repo.get(Sandbox, id), :sandbox)

  defp resolve_sandbox(_), do: error_changeset(%Sandbox{}, :sandbox, "is unknown")

  defp resolve_destination(%Agent{} = agent), do: {:ok, {:agent, agent}}
  defp resolve_destination(%Resource{} = resource), do: {:ok, {:resource, resource}}

  defp resolve_destination(%{"type" => "agent", "id" => id}) when is_integer(id),
    do: fetch(Repo.get(Agent, id), :destination) |> wrap_destination(:agent)

  defp resolve_destination(%{"type" => "resource", "id" => id}) when is_integer(id),
    do: fetch(Repo.get(Resource, id), :destination) |> wrap_destination(:resource)

  defp resolve_destination(_),
    do: error_changeset(%Agent{}, :destination, "must be an agent or a resource")

  defp wrap_destination({:ok, record}, kind), do: {:ok, {kind, record}}
  defp wrap_destination(error, _kind), do: error

  defp fetch(nil, field), do: error_changeset(field_module(field), field, "is unknown")
  defp fetch(record, _field), do: {:ok, record}

  defp field_module(:project), do: %Project{}
  defp field_module(:user), do: %User{}
  defp field_module(:agent), do: %Agent{}
  defp field_module(:approval), do: %Approval{}
  defp field_module(:connection), do: %Connection{}
  defp field_module(:sandbox), do: %Sandbox{}
  defp field_module(:destination), do: %Agent{}
  defp field_module(:resource), do: %Resource{}

  defp error_changeset(schema, field, message) do
    {:error, change(schema) |> add_error(field, message)}
  end

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) and not is_nil(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end
end
