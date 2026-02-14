# Infrastructure Repository

This repository contains the full infrastructure-as-code
for the platform, including:

- Networking (WireGuard mesh)
- Reverse proxy (Traefik)
- Observability (Prometheus, Grafana, Loki)
- Container registry (Harbor)
- VPN infrastructure (VLESS / Xray)
- Application stacks (bots, APIs, workers)

## Infrastructure Docs
- [Harbor Registry](docs/harbor.md)
- [Profiles Artifact Pipeline](docs/profiles-artifact.md)

Current state:
- 
- Swarm manager: A
- Workers: none / partial

## Executable scripts and Git permissions

This repository follows Infrastructure as Code (IaC) principles.
All deployment and bootstrap scripts are executed directly from Git.

### Important note about executable permissions

Shell scripts under the `scripts/` directory (e.g. `bootstrap.sh`) are stored
in Git with the executable bit enabled (`100755`).

This is intentional.

The executable permission is part of the Git index and must be set **once**
using:

```bash
git update-index --chmod=+x scripts/bootstrap.sh
git commit -m "Make bootstrap script executable"
```
