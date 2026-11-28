# Mycelium Core Domain 0.1.0

Public Elixir surface of capability `mycelium.mycelium-core`. Consumers SHALL
depend on this interface, not on generated file organization. The Hex package
name is `mycelium_core`; every public module lives inside the `Mycelium.Core`
namespace.

## Conventions

- Persistence is Ecto over PostgreSQL. Consumers own the Repo's supervision
  and configuration; the domain supplies the schema modules and migrations.
- All mutation functions go through `Mycelium.Core` (the context module) so
  trust rules and policy evaluation are applied exactly once. Consumers SHALL
  NOT insert into schema tables directly.
- Timestamps are UTC; JSON columns (`policy`, payload, config) are validated
  as maps.

## Exported modules and symbols

### Schemas (`Mycelium.Core.{Project,User,Credential,Agent,Resource,Sandbox,Connection,Approval}`)

Struct-backed Ecto schemas for the eight domain tables. Fields and relations
follow the component specification's requirements; `Sandbox.subject_type` is
`agent` or `resource` with `subject_id` pointing at the owner row.

### `Mycelium.Core` (context)

- `create_project/1` — creates a project from attrs (`name`, `repo_url`,
  `default_branch`, optional `policy`); returns `{:ok, project}`.
- `add_user/2` — `add_user(project, attrs)` adds a user; the first user of an
  empty project is self-approved, later users require `approved_by_user_id`
  of an approved user. Returns `{:ok, user}` or `{:error, changeset}`.
- `add_credential/2` — attaches an `ssh_key` or `api_key` credential to a
  user; returns `{:ok, credential}`.
- `add_agent/3` — `add_agent(project, owner, attrs)` adds an agent trusted
  implicitly; requires an approved owner. Returns `{:ok, agent}`.
- `request_resource/3` — `request_resource(project, requester_agent, attrs)`
  evaluates the project policy: within limits and image allowlist, creates
  the resource plus its sandbox row (`{:ok, resource, :policy_auto}`);
  otherwise records a pending `add_resource` approval
  (`{:ok, approval, :queued}`). Rejects requests from agents whose owner is
  not approved.
- `connect/3` — `connect(from_agent, to_subject, protocol)` applies the three
  connection rules: auto-activates (`{:ok, connection, :auto}`) or queues a
  `connect_agents` approval for the destination agent's owner
  (`{:ok, approval, :queued}`).
- `decide_approval/3` — `decide_approval(approval, decider, :approved |
  :denied)` applies the decision exactly once (second decision on a
  decided approval is rejected); approving a queued `connect_agents`
  activates the connection, approving a queued `add_resource` creates the
  resource and sandbox. Returns `{:ok, effect}`.
- `set_connection_state/3` — moves an active connection to `revoked` or
  `closed`; returns `{:ok, connection}`.
- `record_sandbox_state/3` — caches gateway state (`gateway_state`,
  observed at `state_cached_at`) on a sandbox row; `{:ok, sandbox}`.
- `bind_sandbox_gateway/3` — records the gateway sandbox name on a sandbox
  row (`gateway_sandbox_name`, `image`); passing `nil` as the name clears the
  binding; `{:ok, sandbox}`.
- `set_connection_custody/2` — records or clears a connection's tailcat
  custody map (`connection.tailcat`); `{:ok, connection}`.

## Non-goals for 0.1.0

Gateway calls, tailcat address brokerage, and sandbox lifecycle execution
live in consuming Components; this surface stores and governs the records
only. No authentication/authorization enforcement beyond the trust rules
stated in the component specification.
