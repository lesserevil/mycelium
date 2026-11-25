# OpenShell gateway API contract (vendored)

The `.proto` files in `proto/` are vendored verbatim from
`github.com/ai-openshell/openshell`, branch `main`, commit
`aa2efd362b894c87663571695b8363092a7d9c7f` (path `proto/`), fetched 2026-11-25.
Upstream license: Apache-2.0, Copyright NVIDIA CORPORATION & AFFILIATES.

They are the public gateway API closure per upstream `proto/README.md`:

- `openshell.proto` — the gateway gRPC services (the surface this client mirrors)
- `sandbox.proto`, `datamodel.proto`, `options.proto` — transitive imports

Excluded on purpose (upstream classifies them as internal/non-SDK):
`compute_driver`, `credential_driver`, `extension`, `gateway_interceptor`,
`isolation_backend`, `pagination`, `sandbox_protocol`, `supervisor_host`,
`supervisor_middleware`, `test`. Well-known types
(`google/protobuf/descriptor.proto`, `duration.proto`, `struct.proto`,
`timestamp.proto`) come from the protobuf runtime, not this directory.

The upstream commit pin is component authority: updating these files requires
an authored change to this component and a re-review of the affected surface.
