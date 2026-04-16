# Terraform Layout

Terraform manages VPS server provisioning for the K3s cluster and Yandex Cloud VPN nodes.

- Terraform version: `>= 1.8.0, < 2.0.0`

- `terraform/infra-nodes`
  - declarative non-VPN infra node catalog (manager / workers)
  - optional Timeweb API enrichment
  - generated inventory artifact for infra nodes
- `terraform/yandex-vpn`
  - Yandex Cloud VPN entry nodes (adopt existing + create new)
  - non-YC VPN nodes are managed through `vpn-control-api` (admin UI + installer one-liner),
    not Terraform

Remote backend examples:

- `terraform/backends/infra-nodes.hcl.example`
- `terraform/backends/yandex-vpn.hcl.example`

State key recommendation:

- `infra-nodes.tfstate`
- `yandex-vpn.tfstate`

Development var-files (used by `.github/workflows/infra-deploy-dev.yml`):

- `terraform/infra-nodes/catalog.dev.tfvars`
- `terraform/yandex-vpn/catalog.dev.tfvars`
