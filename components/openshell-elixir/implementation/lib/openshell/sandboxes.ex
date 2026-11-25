# Sandbox surface of the OpenShell gateway.
#
#   - `list/3` — `list(client, workspace, timeout)` returns the page of
#     sandbox records for the workspace.
#   - `get/3` — `get(client, workspace, name)` returns `{:ok, sandbox}` or
#     `{:error, %GRPC.RPCError{code: :not_found}}` when absent.
#   - `create/4` — `create(client, workspace, spec, timeout)` creates a
#     sandbox from `spec` (a map shaped like the contract's `SandboxSpec`).
#   - `delete/3` — `delete(client, workspace, name)` deletes the sandbox and
#     returns `{:ok, :deleted}`.
defmodule Openshell.Sandboxes do
  @moduledoc false

  def list(client, workspace, timeout), do: Openshell.Client.list_sandboxes(client, workspace, timeout)
  def get(client, workspace, name), do: Openshell.Client.get_sandbox(client, workspace, name)
  def create(client, workspace, spec, timeout), do: Openshell.Client.create_sandbox(client, workspace, spec, timeout)
  def delete(client, workspace, name), do: Openshell.Client.delete_sandbox(client, workspace, name)
end
