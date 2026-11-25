# Mycelium

A project-level, multi-user manager for agent and container sandboxes.

Mycelium creates and supervises sandboxes (agents and containers) for a
project, and wires them together with managed
[tailcat](https://github.com/tailscale/tailcat) interconnects — secure
point-to-point tunnels over Tailscale's data plane, with no control plane or
account required. Sandbox configuration (what to run, who can reach what, how
sandboxes interconnect) is managed centrally, not per-sandbox.

## Status

Early scaffold. Nothing here yet beyond the OTP application skeleton.

## Development

```sh
mix test
```
