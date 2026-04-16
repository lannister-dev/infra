# vpn-infra

Infrastructure as Code repository for the VPN platform.

## Stack

- Terraform: Yandex Cloud VPN nodes + non-VPN infra-node catalogs.
- Ansible: K3s server/agent bootstrap on infra nodes.
- K3s + Helm (`k8s/`): runtime orchestration.
- WireGuard + Xray: VPN data plane (deployed as K8s workloads).
- `vpn-control-api`: source of truth for VPN-node lifecycle (admin UI +
  installer one-liner); not part of this repo.

## IaC model

Terraform roots:
- `terraform/yandex-vpn` — Yandex Cloud VPN entry nodes (adopt existing + create new).
- `terraform/infra-nodes` — non-VPN infra nodes (K3s managers/workers).

Non-YC VPN nodes are **not** managed by Terraform. They are created and tracked inside
`vpn-control-api`; the admin UI emits a bootstrap one-liner that joins the node to the
K3s cluster, and Helm takes over from there.

Topology source of truth:
- `terraform/yandex-vpn/catalog.auto.tfvars`
- `terraform/infra-nodes/catalog.auto.tfvars`

Secrets and provider credentials stay in local `.env` / Vault.

## Docs

- `docs/terraform.md`
- `docs/ansible.md`
- `docs/yandex-vpn.md`
- `docs/infra-nodes.md`
- `docs/operations-runbook.md`
- `docs/harbor.md`
- `docs/profiles-artifact.md`
- `docs/nats.md`
- `docs/data-dev.md`
- `docs/data-prod-migration.md`
- `docs/infra-env-dev.example`
- `docs/infra-env-prod.example`

## Scripts

- `scripts/core` — operational helpers used in the active CI/CD flow.
- `scripts/ci` — helpers used exclusively from GitHub Actions.

Reference: `scripts/README.md`.

## K8s bootstrap

`k8s/bootstrap/install-agent.sh` is the current manual K3s join helper. It will be
replaced by the installer shipped by `vpn-control-api` once the admin UI "Add Node" flow
lands.
