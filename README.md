# Mycelium

A project-level, multi-user manager for agent and container sandboxes.

Mycelium creates and supervises sandboxes (agents and containers) for a
project, and wires them together with managed
[tailcat](https://github.com/tailscale/tailcat) interconnects — secure
point-to-point tunnels over Tailscale's data plane, with no control plane or
account required. Sandbox configuration (what to run, who can reach what, how
sandboxes interconnect) is managed centrally, not per-sandbox.

## Sandbox runtime: NVIDIA OpenShell

Sandboxes are [OpenShell](https://github.com/nvidia/openShell) sandboxes: an
OpenShell gateway is the control plane that creates, supervises, and deletes
them, enforces declarative policy (filesystem, process, network), and brokers
credentials. Mycelium manages sandboxes through that gateway rather than
touching container runtimes (Docker, Podman, MicroVM, Kubernetes) directly —
the runtime is the gateway's `compute_driver` setting, not Mycelium's concern.

Mycelium integrates with OpenShell via the `openshell` CLI (the CLI drives the
gateway and emits machine-readable output). OpenShell has no Elixir SDK; the
gateway also speaks gRPC, which we can adopt later if the CLI becomes a
limitation.

## Status

Early scaffold. Nothing here yet beyond the OTP application skeleton.

## Development

```sh
mix test
```
