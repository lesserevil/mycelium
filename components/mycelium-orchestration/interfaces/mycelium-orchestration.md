# Mycelium Sandbox Orchestration 0.1.0

Public Elixir surface of capability `mycelium.mycelium-orchestration`.
Consumers SHALL depend on this interface, not on generated file organization.
The Hex package name is `mycelium_orchestration`; every public module lives
inside the `Mycelium.Orchestration` namespace.

## Conventions

- All functions take a connected gateway client (`Openshell.Client.t()`) plus
  domain records from `mycelium.mycelium-core`. Domain mutations go through
  the core context; this surface never writes domain tables directly.
- Returns are `{:ok, term}` / `{:error, term}`; gateway failures surface the
  structured `GRPC.RPCError` from the client capability.

## Exported modules and symbols

### `Mycelium.Orchestration`

- `ensure_sandbox/2` — `ensure_sandbox(client, sandbox)` binds a domain
  sandbox row (agent or resource subject) to a real gateway sandbox: refuses
  images outside the project's `image_allowlist`, creates the gateway sandbox
  exactly once for an unbound row, records the gateway sandbox name, and
  refreshes the cached state. Returns `{:ok, sandbox}`.
- `refresh_sandbox_state/2` — `refresh_sandbox_state(client, sandbox)` reads
  the gateway sandbox and caches the observation through the core domain.
  Returns `{:ok, sandbox}`.
- `open_connection/2` — `open_connection(client, connection)` drives an
  approved connection to dial-ready via the check-in/poll handshake
  (schedule `serve` on the destination, record its check-in address, schedule
  `dial` for the source). Returns `{:ok, connection}`.
- `close_connection/2` — clears tailcat custody and stops serving dial
  assignments for the connection. Returns `{:ok, connection}`.
- `delete_sandbox/2` — `delete_sandbox(client, sandbox)` deletes the gateway
  sandbox and clears the domain binding; refuses while an `active` connection
  references the subject. Returns `:ok` or `{:error, reason}`.
- `register_check_in/4` — `register_check_in(sandbox, role, address, opts)`
  records a supervisor check-in; idempotent for identical input; refuses
  unknown/unbound sandboxes. `role` is `serve`. Returns `{:ok, assignment}`
  or `{:error, reason}`.
- `pending_assignments/1` — `pending_assignments(sandbox)` returns the dial
  assignments the supervisor should act on:
  `{:ok, [%{"connection" => id, "role" => "dial", "address" => addr}]}`.

### Supervisor protocol payloads (owned here, hosted by the service component)

- check-in body: `{"sandbox": <gateway sandbox name>, "role": "serve",
  "address": <tailcat address>}`
- poll body: `{"assignments": [{"connection": <id>, "role": "dial",
  "address": <tailcat address>}]}`

## Non-goals for 0.1.0

Hosting endpoints, image building/upload, a2a payload handling, gateway
stop/start/exec, and multi-replica gateway coordination are out of scope.
