# Scripts Inventory

This directory is split into:

- `scripts/core`: operational scripts used by current IaC workflow.
- `scripts/legacy`: fallback/migration scripts kept for emergencies or one-time tasks.

## Core scripts

- `scripts/core/prepare-terraform-env.sh`
  Converts `IAC_TFVAR_*` aliases to `TF_VAR_*` for Terraform in CI/deploy.
- `scripts/core/sanity-check.sh`
  Post-deploy sanity checks (called by Ansible deploy playbook).
- `scripts/core/swarm-label-node.sh`
  Idempotent Swarm node labeling helper (`role/channel/peer_name`), returns rc `10` on change.
- `scripts/core/swarm-label-infra-node.sh`
  Idempotent Swarm node labeling helper for infra nodes (`kind/infra_name/provider/region`), returns rc `10` on change.
- `scripts/core/swarm-refresh-registry-auth.sh`
  Idempotent helper to refresh registry auth for a Swarm service, returns rc `10` on change.
- `scripts/core/update-terraform-locks.sh`
  Updates provider lock files (`.terraform.lock.hcl`) for all roots.

## Legacy scripts

- `scripts/legacy/add-node.sh`
  Emergency/manual node onboarding (non-declarative fallback).
- `scripts/legacy/bootstrap.sh`
  Host bootstrap fallback (Terraform/Ansible remain primary flow).
- `scripts/legacy/terraform-import-foundation.sh`
  One-time migration helper to import existing Docker resources into Terraform state.

## Policy

- New automation must go through Terraform + Ansible first.
- Add scripts to `core` only if they are part of day-2 operations.
- Put one-off migration and manual break-glass tools into `legacy`.
- CI quality gates validate `scripts/core` and active `wireguard/manager` scripts; `scripts/legacy` is intentionally excluded from the main pipeline.
