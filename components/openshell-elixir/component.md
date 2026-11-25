---
namespace: mycelium
version: 0.1.0
display_name: OpenShell Elixir Client
kind: library
profiles:
  - library
sample: false
provides:
  - name: mycelium.openshell-elixir
    version: 0.1.0
    interface:
      uri: interfaces/openshell-elixir.md
      pin: null
  - name: sample.portable-app
    version: 1.0.0
    interface: null
requires: []
authoring_inputs:
  - kind: specification-to-source-skill
    uri: skills/specification-to-source/portable-application-implementation/SKILL.md
  - kind: specification-to-source-skill
    uri: skills/specification-to-source/portable-specification-planning/SKILL.md
workflow_definition:
  uri: workflows/production/staging/dev/workflow.md
routing_policy:
  uri: routing/production/staging/dev/routing.json
flavor_slots:
  - slot_id: build-system
    axis: build.system
    cardinality: exactly-one
    capability_contract: mycelium.openshell-elixir
  - slot_id: language
    axis: implementation.language-ecosystem
    cardinality: exactly-one
    capability_contract: sample.portable-app
  - slot_id: os
    axis: platform.os
    cardinality: exactly-one
    capability_contract: sample.portable-app
  - slot_id: toolchain
    axis: toolchain
    cardinality: zero-or-one
    capability_contract: mycelium.openshell-elixir
entrypoints: []
acceptance_contracts: []
source_dependencies: []
---
# OpenShell Elixir Client

This Component is the Elixir client SDK for the NVIDIA OpenShell gateway API. It
speaks the gateway's gRPC contract (`openshell.v1`) on behalf of consumers —
Mycelium's sandbox manager first, any other Elixir caller second — so that no
consumer needs to shell out to the `openshell` CLI or own protobuf tooling.

```mermaid
flowchart LR
    C["Elixir consumer"] --> S["Openshell client surface"]
    S --> G["OpenShell gateway (gRPC, openshell.v1)"]
```

The OpenShell project ships SDKs for Go, Rust, Python, and TypeScript but not
Elixir. This Component fills that gap as a faithful client of the declared
gateway contract, vendored under `contract/proto/`.

## Application contract

| Concern | Decision |
| --- | --- |
| Component kind | `library` (no product entrypoint) |
| Hex package name | `openshell` |
| Module namespace | `Openshell` (public modules live inside it) |
| Wire contract | `openshell.v1` services from the vendored `contract/proto/` |
| Error convention | `{:ok, term} \| {:error, %GRPC.RPCError{}}` |
| Transport | gRPC over HTTP/2 (TLS by default, plaintext opt-in for local gateways) |

The public module surface is defined by `interfaces/openshell-elixir.md`; consumers
SHALL depend on that interface rather than any generated file organization.

### Requirement: Mirror the declared gateway contract

The Component SHALL derive every message and service stub from the vendored
`contract/proto/` files and SHALL NOT hand-maintain a parallel schema. The vendored
upstream commit pin (`contract/README.md`) is the contract identity; updating it is
an authored change to this Component.

#### Scenario: Gateway stubs come from the vendored contract

- **WHEN** the client calls any gateway RPC
- **THEN** the request and response messages are types generated from the vendored
  `openshell.v1` contract, and a gateway that drifts from that contract fails the
  call with a structured gRPC status rather than a partially-valid exchange

### Requirement: Structured failures only

Every failing call SHALL return `{:error, %GRPC.RPCError{}}` carrying the canonical
gRPC status code; the Component SHALL NOT raise across the public surface for
expected remote failures and SHALL NOT return bare strings or ad-hoc error tuples.

#### Scenario: Unreachable gateway

- **WHEN** `connect/2` targets an address with no gateway listener
- **THEN** the caller receives `{:error, reason}` without a raised exception

### Requirement: Credentials stay out of logs and errors

The Component SHALL NOT include bearer tokens, sandbox JWTs, or other credentials
in exception messages, log output, or error payloads.

#### Scenario: Authenticated failure

- **WHEN** a call is rejected for bad credentials
- **THEN** the returned error identifies the status code and no token material
