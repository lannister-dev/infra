# vpn-infra

Infrastructure as Code repository for VPN platform operations.

## Stack

- Terraform: infrastructure state and node catalogs
- Ansible: reconciliation and deployment
- Docker Swarm: runtime orchestration
- WireGuard + Xray: VPN data plane

## IaC model

Terraform is the control plane:
- `terraform/foundation` for Swarm foundation resources
- `terraform/nodes` for VPN nodes
- `terraform/infra-nodes` for non-VPN infra nodes

Topology source of truth:
- `terraform/nodes/catalog.auto.tfvars`
- `terraform/infra-nodes/catalog.auto.tfvars`

Secrets and provider credentials stay in local `.env` / CI secrets.

## Docs

- `docs/terraform.md`
- `docs/ansible.md`
- `docs/vpn-nodes-api.md`
- `docs/infra-nodes.md`
- `docs/add-vpn-node.md`
- `docs/operations-runbook.md`
- `docs/harbor.md`
- `docs/profiles-artifact.md`
- `docs/nats.md`
- `docs/infra-env-dev.example`

## Note on scripts

Scripts are organized by lifecycle:
- `scripts/core` for current operational helpers used in active CI/CD flow.
- `scripts/legacy` for break-glass and one-time migration scripts (stored for reserve, not part of the main flow).

Reference: `scripts/README.md`.

Shell scripts in `scripts/` are operational helpers and emergency fallback tools.
Primary production flow is Terraform + Ansible.
