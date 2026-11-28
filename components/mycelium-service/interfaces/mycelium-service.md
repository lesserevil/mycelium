# Mycelium Service 0.1.0

Public Elixir surface of capability `mycelium.mycelium-service`. Consumers
SHALL depend on this interface, not on generated file organization. The Hex
package name is `mycelium_service`; every public module lives inside the
`Mycelium.Service` namespace.

## Conventions

- This component's own application module (`MyceliumService.Application`)
  supervises `Mycelium.Core.Repo` and runs `Mycelium.Service.Endpoint` under
  Bandit; `mix run --no-halt` from the implementation projection is the
  running Mycelium service.
- JSON bodies use string keys; responses are `{"ok": true}` or
  `{"error": {"code": ..., "message": ...}}` with an appropriate HTTP status
  (200 / 400 / 401 / 404).

## Exported modules and symbols

### `Mycelium.Service.Endpoint`

A Plug router serving the supervisor protocol:

- `POST /mycelium/v1/checkin` — body
  `{"sandbox": ..., "role": "serve", "connection": <id>, "address": ...}`;
  delegates to `Mycelium.Orchestration.register_check_in/4` after resolving
  the sandbox row by gateway name.
- `POST /mycelium/v1/poll` — body `{"sandbox": ...}`; responds with
  `{"assignments": [...]}` from `Mycelium.Orchestration.pending_assignments/1`.

Bearer-token auth is optional and configured by the host application.

### `Mycelium.Service`

- `check_in/2` — `check_in(conn_or_body, opts)` handles one check-in payload;
  returns `{:ok, connection}` or `{:error, {status, code, message}}` where
  `status` is the HTTP status.
- `poll/2` — `poll(sandbox_name, opts)` returns `{:ok, assignments}` or
  `{:error, {404, "unknown_sandbox", message}}`.
- `provision_agent_sandbox/3` — `provision_agent_sandbox(client, agent,
  image)` creates the agent's domain sandbox row (core context) and binds it
  to a real gateway sandbox (orchestration) in one call; refuses an agent
  with an already-bound row. Returns `{:ok, sandbox}` or
  `{:error, {status, code, message}}`.
- `resolve_sandbox_by_gateway_name/1` — `resolve_sandbox_by_gateway_name(name)`
  returns `{:ok, sandbox}` or `:error`; the read-only lookup behind both
  endpoint routes.

### Reference supervisor (`supervisor/mycelium-supervisor`)

A POSIX shell script serving as the contract reference for image authors.
Environment: `MYCELIUM_ENDPOINT` (base URL), `MYCELIUM_GATEWAY_SANDBOX_NAME`
(the sandbox's own gateway name), optional `MYCELIUM_TOKEN`. Behavior:
poll on an interval; start one `tailcat` listener per serve assignment and
check in its address; dial each dial assignment; tear down when assignments
disappear; exit non-zero after a sustained endpoint outage. 0.1 limitation:
tunnels are stdio pipes (no port forwarding).

## Non-goals for 0.1.0

User-facing management endpoints, approval workflows, gateway stop/start,
connection ports, multi-replica deployments.
