# Terraform Layout

Terraform manages VPS server provisioning for the K3s cluster.

- Terraform version: `>= 1.8.0, < 2.0.0`

- `terraform/nodes`
  - declarative desired VPN node catalog
  - generated Ansible inventory for node reconciliation
- `terraform/infra-nodes`
  - declarative non-VPN infra node catalog (manager/workers)
  - optional Timeweb API enrichment
  - generated inventory artifact for infra nodes

Remote backend examples:

- `terraform/backends/nodes.hcl.example`
- `terraform/backends/infra-nodes.hcl.example`

State key recommendation:

- `nodes.tfstate`
- `infra-nodes.tfstate`

Development var-files (used by `.github/workflows/infra-deploy-dev.yml`):

- `terraform/nodes/catalog.dev.tfvars`
- `terraform/infra-nodes/catalog.dev.tfvars`
