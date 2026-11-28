defmodule Mycelium.Service do
  @moduledoc """
  Service-level operations: the supervisor check-in/poll handlers and agent
  sandbox provisioning. The endpoint delegates here; both resolve sandboxes
  by gateway sandbox name.
  """

  import Ecto.Query

  alias Mycelium.Core
  alias Mycelium.Core.Repo
  alias Mycelium.Core.Sandbox
  alias Mycelium.Orchestration

  @typedoc "{http_status, code, message}"
  @type error :: {200 | 400 | 401 | 404 | 409, String.t(), String.t()}

  # -- Supervisor protocol handlers -------------------------------------------

  @doc """
  Handles one check-in payload (string-keyed map from JSON). Refuses unknown
  sandboxes (404), malformed payloads (400), and unknown connections (404).
  """
  @spec check_in(map(), keyword()) :: {:ok, Mycelium.Core.Connection.t()} | {:error, error()}
  def check_in(payload, _opts \\ []) when is_map(payload) do
    with {:ok, sandbox} <- resolve(payload["sandbox"]),
         :ok <- require_integer(payload["connection"], "connection"),
         :ok <- require_binary(payload["address"], "address"),
         :ok <- require_role(payload["role"]) do
      case Orchestration.register_check_in(
             sandbox,
             :serve,
             payload["address"],
             connection: payload["connection"]
           ) do
        {:ok, connection} -> {:ok, connection}
        {:error, reason} -> {:error, {404, "check_in_refused", to_message(reason)}}
      end
    end
  end

  @doc "Returns the sandbox's desired assignment state."
  @spec poll(String.t() | nil, keyword()) :: {:ok, [map()]} | {:error, error()}
  def poll(sandbox_name, opts \\ [])

  def poll(sandbox_name, _opts) when is_binary(sandbox_name) do
    with {:ok, sandbox} <- resolve(sandbox_name) do
      case Orchestration.pending_assignments(sandbox) do
        {:ok, assignments} -> {:ok, assignments}
        {:error, reason} -> {:error, {404, "poll_refused", to_message(reason)}}
      end
    end
  end

  def poll(_sandbox_name, _opts), do: {:error, {400, "malformed", "sandbox is required"}}

  # -- Agent provisioning -------------------------------------------------------

  @doc """
  Creates the agent's domain sandbox row and binds it to a real gateway
  sandbox in one call. Refuses agents that already have a sandbox row (409).
  """
  @spec provision_agent_sandbox(Openshell.Client.t(), Mycelium.Core.Agent.t() | integer(), String.t()) ::
          {:ok, Sandbox.t()} | {:error, error()}
  def provision_agent_sandbox(client, agent, image) do
    with %Mycelium.Core.Agent{id: id} <- resolve_agent(agent),
         :ok <- require_binary(image, "image") do
      case Core.create_sandbox(:agent, id, %{"image" => image}) do
        {:ok, sandbox} ->
          case Orchestration.ensure_sandbox(client, sandbox) do
            {:ok, bound} -> {:ok, bound}
            {:error, reason} -> {:error, {502, "gateway_refused", to_message(reason)}}
          end

        {:error, changeset} ->
          if duplicate_row?(changeset) do
            {:error, {409, "already_provisioned", "agent already has a sandbox row"}}
          else
            {:error, {400, "invalid", to_message(changeset.errors)}}
          end
      end
    else
      nil -> {:error, {404, "unknown_agent", "agent is unknown"}}
      error -> error
    end
  end

  # -- Shared lookups -------------------------------------------------------------

  @doc "Read-only lookup of a bound sandbox row by gateway sandbox name."
  @spec resolve_sandbox_by_gateway_name(String.t()) :: {:ok, Sandbox.t()} | :error
  def resolve_sandbox_by_gateway_name(name) when is_binary(name) do
    case Repo.one(from(s in Sandbox, where: s.gateway_sandbox_name == ^name)) do
      %Sandbox{} = sandbox -> {:ok, sandbox}
      nil -> :error
    end
  end

  def resolve_sandbox_by_gateway_name(_name), do: :error

  defp resolve(name) when is_binary(name) do
    case resolve_sandbox_by_gateway_name(name) do
      {:ok, sandbox} -> {:ok, sandbox}
      :error -> {:error, {404, "unknown_sandbox", "no bound sandbox named #{inspect(name)}"}}
    end
  end

  defp resolve(_name), do: {:error, {400, "malformed", "sandbox is required"}}

  defp resolve_agent(%Mycelium.Core.Agent{} = agent), do: agent
  defp resolve_agent(id) when is_integer(id), do: Repo.get(Mycelium.Core.Agent, id)
  defp resolve_agent(_), do: nil

  defp duplicate_row?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {msg, _opts}} -> msg =~ "already has a sandbox row" end)
  end

  defp require_role("serve"), do: :ok
  defp require_role(:serve), do: :ok
  defp require_role(other), do: {:error, {400, "malformed", "role must be serve, got #{inspect(other)}"}}

  defp require_integer(value, _field) when is_integer(value), do: :ok
  defp require_integer(_value, field), do: {:error, {400, "malformed", field <> " must be an integer"}}

  defp require_binary(value, _field) when is_binary(value) and value != "", do: :ok
  defp require_binary(_value, field), do: {:error, {400, "malformed", field <> " must be a nonempty string"}}

  defp to_message(reason) when is_binary(reason), do: reason

  defp to_message(errors) when is_list(errors) do
    errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
    |> Enum.join("; ")
  end

  defp to_message(reason), do: inspect(reason)
end
