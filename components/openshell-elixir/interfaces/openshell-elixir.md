# OpenShell Elixir Client 0.1.0

Public Elixir surface of capability `mycelium.openshell-elixir`. Consumers SHALL
depend on this interface, not on generated file organization. The Hex package name
is `openshell`; every public module lives inside the `Openshell` namespace.

## Conventions

- A connected gateway is a client value created by `Openshell.Client.connect/2`.
  Passing values between the functions below is the only supported use.
- Every call returns `{:ok, term}` or `{:error, %GRPC.RPCError{}}`; no expected
  failure raises. `GRPC.RPCError.status` carries the canonical integer gRPC
  status code (for example `status: 5` for not-found); match with the integer
  or `GRPC.Status.is_rpc_error/2` guards.
- Workspaces are canonical workspace names (`"default"` is explicit, never implied).
- Timeouts and call options are keyword lists forwarded to the transport layer;
  semantics follow the underlying gRPC client library.

## Exported modules and symbols

### `Openshell.Client`

- `connect/2` — `connect(opts, timeout)` opens a channel to a gateway. `opts`
  accepts `:address` (required, `"host:port"`), `:tls` (`true` by default; `false`
  for local plaintext), `:ca` (CA certificate file or PEM contents), `:cert` and
  `:key` (client certificate and private key, file path or PEM contents, for mTLS
  gateways), and `:token` (bearer credential, optional for local gateways).
  Returns `{:ok, client}` or `{:error, reason}`.
- `close/1` — closes a client's channel; returns `:ok`.

### `Openshell.Health`

- `check/2` — `check(client, timeout)` reports gateway health; returns
  `{:ok, :healthy}`, `{:ok, :degraded}`, or `{:error, reason}`.

### `Openshell.Sandboxes`

- `list/3` — `list(client, workspace, timeout)` returns
  `{:ok, sandboxes}` where `sandboxes` is the page of sandbox records for the
  workspace.
- `get/3` — `get(client, workspace, name)` returns `{:ok, sandbox}` or
  `{:error, %GRPC.RPCError{status: 5}}` (`GRPC.Status.not_found()`) when absent.
- `create/4` — `create(client, workspace, spec, timeout)` creates a sandbox from
  `spec` — a map with `:image` (required), `:command` (binary or list of
  binaries), and optional `:name` (server generates a name when omitted) and
  `:sizing` (map forwarded as the template's driver resources) — and returns
  `{:ok, sandbox}`. Deletion is asynchronous on the gateway: `delete/3` returns
  `{:ok, :deleted}` once accepted, and the record remains readable until the
  gateway finishes tearing it down.
- `delete/3` — `delete(client, workspace, name)` deletes the sandbox and returns
  `{:ok, :deleted}`.

## Non-goals for 0.1.0

Exec, file transfer, SSH, TCP forwarding, policy, providers, templates, and
workspace management RPCs are not in this surface; they follow in later versions
as additive exports. Generated protobuf modules beneath `Openshell.V1` are
implementation detail and not part of this contract.
