# Terraform Layout

Terraform is split into two root modules with separate state:

- Terraform version: `>= 1.8.0, < 2.0.0`

- `terraform/foundation`
  - overlay networks
  - persistent volumes
  - docker configs rendered from repository files/templates
- `terraform/nodes`
  - declarative desired VPN node catalog
  - generated Ansible inventory for node reconciliation
- `terraform/infra-nodes`
  - declarative non-VPN infra node catalog (manager/workers)
  - optional Timeweb API enrichment
  - generated inventory artifact for infra nodes

Remote backend examples:

- `terraform/backends/foundation.hcl.example`
- `terraform/backends/nodes.hcl.example`
- `terraform/backends/infra-nodes.hcl.example`

State key recommendation:

- `foundation.tfstate`
- `nodes.tfstate`
- `infra-nodes.tfstate`
