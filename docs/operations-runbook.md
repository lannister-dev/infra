# Operations Runbook

Run all commands from repo root on the automation runner/manager (`/opt/vpn-infra`).

## 1. Health checks

```bash
docker node ls
docker stack ls
docker service ls
wg show
```

Terraform state checks:

```bash
terraform -chdir=terraform/foundation state list
terraform -chdir=terraform/nodes state list
terraform -chdir=terraform/infra-nodes state list
```

## 2. Standard deploy cycle

```bash
set -a
source .env
set +a

export REPO_ROOT="$(pwd)"
export ANSIBLE_CONFIG="$(pwd)/ansible/ansible.cfg"

terraform -chdir=terraform/foundation init -input=false -backend-config="$(pwd)/terraform/backends/foundation.hcl"
terraform -chdir=terraform/foundation apply -input=false -auto-approve

terraform -chdir=terraform/nodes init -input=false -backend-config="$(pwd)/terraform/backends/nodes.hcl"
terraform -chdir=terraform/nodes apply -input=false -auto-approve

terraform -chdir=terraform/infra-nodes init -input=false -backend-config="$(pwd)/terraform/backends/infra-nodes.hcl"
terraform -chdir=terraform/infra-nodes apply -input=false -auto-approve

ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/reconcile-vpn-nodes.yml
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/deploy-stacks.yml
```

CI policy:
- `.github/workflows/infra-ci.yml`: checks only on `pull_request` and `push/main`.
- `.github/workflows/infra-deploy.yml`: production apply only from `workflow_dispatch` with `confirm_apply=APPLY`.
- Terraform variables in CI are centralized via `TF_VAR_*` (or `IAC_TFVAR_*` aliases).

## 3. VPN node lifecycle

Source of truth: `terraform/nodes/catalog.auto.tfvars`.

Add node:
1. Add entry into one of maps (`vpn_nodes`, `provider_api_vpn_nodes`, `provider_compute_vpn_nodes`).
2. Apply `terraform/nodes`.
3. Run `reconcile-vpn-nodes.yml`.

Disable node without deleting VPS:
1. Set `enabled = false`.
2. Apply and reconcile.

Destroy compute node:
1. Remove node from `provider_compute_vpn_nodes`.
2. Apply and reconcile.

## 4. Non-VPN infra nodes

Source of truth: `terraform/infra-nodes/catalog.auto.tfvars`.

Add/replace manager or worker:
1. Update `infra_nodes`, `timeweb_infra_nodes`, or `timeweb_provisioned_infra_nodes`.
2. Apply `terraform/infra-nodes`.
3. Ensure bootstrap/join/labels for new node.
4. Re-run `deploy-stacks.yml`.

## 5. Provider incident algorithm (ban/outage)

1. Add replacement nodes on alternate provider/region with `enabled = true`.
2. Apply Terraform and run reconciliation.
3. Verify capacity (`docker node ls`, `wg show`, service health).
4. Only then disable old nodes (`enabled = false`).
5. After full cutover, remove old compute entries to destroy old VPS.

For 10+ nodes, keep multi-provider topology and rotate in batches (blue/green), not all at once.
