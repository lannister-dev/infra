# Scripts Inventory

## Core scripts

- `scripts/core/prepare-terraform-env.sh`
  Converts `IAC_TFVAR_*` aliases to `TF_VAR_*` for Terraform in CI/deploy.
- `scripts/core/render-ansible-ssh-keys.py`
  Materializes SSH keys from `ANSIBLE_SSH_KEYS_B64_JSON` for the `k3s-setup` workflow.
- `scripts/core/update-terraform-locks.sh`
  Updates provider lock files (`.terraform.lock.hcl`) for all roots.
- `scripts/core/backup-data.sh`
  Dumps a managed-data-* PostgreSQL instance running in the K3s cluster.

## CI scripts

- `scripts/ci/apply-terraform.sh`
  Init / plan / apply for `terraform/infra-nodes` and `terraform/yandex-vpn` based on
  `APPLY_INFRA_NODES` / `APPLY_YANDEX_VPN` gates.

## Policy

- New automation must go through Terraform + Helm first.
- Keep break-glass / one-shot tooling out of this repo; if needed, it lives in
  `vpn-control-api` or a dedicated ops repo.
