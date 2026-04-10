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

ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/reconcile-infra-nodes.yml
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/reconcile-vpn-nodes.yml
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/deploy-stacks.yml
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
  - `terraform/foundation/terraform.dev.tfvars`
  - `terraform/nodes/catalog.dev.tfvars`
  - `terraform/infra-nodes/catalog.dev.tfvars`
- For `terraform/foundation`, keep real Xray domains, paths and REALITY values in
  `INFRA_ENV_DEV` as `TF_VAR_*`; there is no fallback from primary fields to dev
  fields. `terraform.dev.tfvars` should only carry repo-safe dev toggles.
- If DB/Redis are hosted outside this repo (manual/external services), enable precheck:
  - `EXTERNAL_DATA_PRECHECK_ENABLED=true`
  - `EXTERNAL_POSTGRES_HOST` / `EXTERNAL_POSTGRES_PORT`
  - `EXTERNAL_REDIS_HOST` / `EXTERNAL_REDIS_PORT`
- If you want managed dev data services in swarm:
  - `DEPLOY_DATA_DEV_STACK=true`
  - set `DEV_POSTGRES_PASSWORD` and `DEV_REDIS_PASSWORD`
- If you want managed prod data services in swarm:
  - `DEPLOY_DATA_PROD_STACK=true`
  - set `PROD_POSTGRES_PASSWORD` and `PROD_REDIS_PASSWORD`

## 3. VPN node lifecycle

Source of truth: `terraform/nodes/catalog.auto.tfvars`.

Add node:
1. Add entry into one of maps (`vpn_nodes`, `provider_api_vpn_nodes`, `provider_compute_vpn_nodes`, `yandex_whitelist_entry_nodes`).
2. Set `ssh_key_ref` for the node (for example `dev`).
3. Ensure matching private key exists in `INFRA_ENV_PROD` via `ANSIBLE_SSH_KEYS_B64_JSON`.
4. Apply `terraform/nodes`.
5. Run `reconcile-vpn-nodes.yml`.
6. Run `deploy-stacks.yml`.

Whitelist entry node specifics:
1. It still joins Swarm as a worker.
2. It must receive `traffic_role=whitelist_entry`.
3. It must not run regular backend stacks `vpn_xray` and `vpn_node-agent`.
4. It runs the dedicated `vpn-whitelist-entry` relay stack instead.
5. Set relay upstream before deploy:
   `VPN_WHITELIST_ENTRY_UPSTREAM_HOST=<backend_ip_or_dns>`
   `VPN_WHITELIST_ENTRY_UPSTREAM_PORT=443`

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
2. Set a dedicated infra `ssh_key_ref` such as `prod_infra`.
3. Ensure matching private key exists in `INFRA_ENV_PROD` via `ANSIBLE_SSH_KEYS_B64_JSON`.
4. Apply `terraform/infra-nodes`.
5. Run `reconcile-infra-nodes.yml` so the new node installs Docker, joins Swarm and gets `kind` labels.
6. Re-run `deploy-stacks.yml`.

## 5. Provider incident algorithm (ban/outage)

1. Add replacement nodes on alternate provider/region with `enabled = true`.
2. Apply Terraform and run reconciliation.
3. Verify capacity (`docker node ls`, `wg show`, service health).
4. Only then disable old nodes (`enabled = false`).
5. After full cutover, remove old compute entries to destroy old VPS.

For 10+ nodes, keep multi-provider topology and rotate in batches (blue/green), not all at once.

## 6. Backup & Restore

### Backup PostgreSQL

Use `scripts/core/backup-data.sh` to dump a Swarm PostgreSQL service:

```bash
# Backup data-prod PostgreSQL (keep last 7 dumps)
./scripts/core/backup-data.sh --service data-prod_postgres --target-dir /opt/backups --retention 7

# Backup data-dev PostgreSQL
./scripts/core/backup-data.sh --service data-dev_postgres --target-dir /opt/backups --retention 5
```

The script finds the running container for the Swarm service, runs `pg_dump`,
compresses the output, and prunes old backups beyond the retention count.

### Restore PostgreSQL

```bash
# Find the container
CONTAINER_ID=$(docker ps --filter "label=com.docker.swarm.service.name=data-prod_postgres" --format '{{.ID}}' | head -n1)

# Restore from backup
gunzip -c /opt/backups/data-prod_postgres/vpn_control_20260411T120000Z.sql.gz \
  | docker exec -i "$CONTAINER_ID" psql -U vpn_prod_user -d vpn_control
```

### Scheduled backups

Add a cron job on the manager node:

```bash
# Every day at 03:00 UTC
0 3 * * * /opt/vpn-infra/scripts/core/backup-data.sh --service data-prod_postgres --target-dir /opt/backups --retention 14 >> /var/log/backup-data.log 2>&1
```
