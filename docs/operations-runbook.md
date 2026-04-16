# Operations Runbook

Run all commands from repo root on the automation runner/manager.

## 1. Health checks

```bash
kubectl get nodes
kubectl get pods -A
```

Terraform state checks:

```bash
terraform -chdir=terraform/infra-nodes state list
terraform -chdir=terraform/yandex-vpn state list
```

## 2. Standard deploy cycle

```bash
set -a
source .env
set +a

export REPO_ROOT="$(pwd)"
export ANSIBLE_CONFIG="$(pwd)/ansible/ansible.cfg"

terraform -chdir=terraform/infra-nodes init -input=false -backend-config="$(pwd)/terraform/backends/infra-nodes.hcl"
terraform -chdir=terraform/infra-nodes apply -input=false -auto-approve

terraform -chdir=terraform/yandex-vpn init -input=false -backend-config="$(pwd)/terraform/backends/yandex-vpn.hcl"
terraform -chdir=terraform/yandex-vpn apply -input=false -auto-approve
```

CI policy:
- `.github/workflows/infra-ci.yml`: checks only on `pull_request` and `push/main`.
- `.github/workflows/infra-deploy.yml`: production apply only from `workflow_dispatch` with `confirm_apply=APPLY`.
- `.github/workflows/infra-deploy-dev.yml`: development apply from `workflow_dispatch` with `confirm_apply=DEV`.
- Terraform variables in CI are centralized via `TF_VAR_*` (or `IAC_TFVAR_*` aliases).
- Vault layout used by deploy workflows:
  - `kv/infra/prod#config`
  - `kv/infra/dev#config`
  - `kv/node-agent/prod#config`
  - `kv/node-agent/dev#config`

Development-specific notes:
- Development deploy also reads Vault:
  - `kv/infra/dev#config`
  - `kv/node-agent/dev#config`
- Use dedicated state prefix in `INFRA_ENV_DEV`, for example `TF_STATE_KEY_PREFIX=vpn-infra/dev`.
- Dev workflow uses explicit var-files:
  - `terraform/infra-nodes/catalog.dev.tfvars`
  - `terraform/yandex-vpn/catalog.dev.tfvars`

## 3. VPN node lifecycle

VPN node onboarding is driven by `vpn-control-api` (admin UI → "Add Node" → bootstrap
one-liner). Terraform no longer owns non-YC VPN compute; the installer script joins the
node to the K3s cluster, applies labels, and from there Helm deploys `node-agent` and
`xray`.

For the Yandex Cloud subset of VPN nodes, see [`yandex-vpn.md`](yandex-vpn.md). Everything
else flows through the admin UI (link TBD).

## 4. Non-VPN infra nodes

Source of truth: `terraform/infra-nodes/catalog.auto.tfvars`.

## 5. Backup & Restore

### Backup PostgreSQL

Use `scripts/core/backup-data.sh`:

```bash
./scripts/core/backup-data.sh --namespace data-prod --pod data-prod-postgres-0
./scripts/core/backup-data.sh --namespace data-dev  --pod data-dev-postgres-0
```
