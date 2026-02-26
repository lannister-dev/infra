# Add VPN Node

Primary flow is fully declarative.

## 1. Update topology

Edit `terraform/nodes/catalog.auto.tfvars`:
- `vpn_nodes` for manual IP,
- or `provider_api_vpn_nodes` for existing server IDs (recommended),
- or `provider_compute_vpn_nodes` for Terraform-managed compute (recommended for frequent rotation).
- set `ssh_key_ref` per node (example: `dev`, `hostvds`, `timeweb`).

Legacy compatibility:
- `hostvds_vpn_nodes` and `hostvds_provisioned_vpn_nodes` still work but are deprecated.

## 2. Apply Terraform nodes state

```bash
set -a
source .env
set +a

terraform -chdir=terraform/nodes init -input=false -backend-config="$(pwd)/terraform/backends/nodes.hcl"
terraform -chdir=terraform/nodes apply -input=false
```

## 3. Reconcile and deploy

```bash
export REPO_ROOT="$(pwd)"
export ANSIBLE_CONFIG="$(pwd)/ansible/ansible.cfg"

ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/reconcile-vpn-nodes.yml
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/deploy-stacks.yml
```

## SSH requirements

- For HostVDS Ubuntu images in this project, use `ssh_user = "root"` in node catalog.
- Server must be created with a known key pair (for example `dev`).
- CI secret `INFRA_ENV_PROD` should provide `ANSIBLE_SSH_KEYS_B64_JSON`:
  - JSON object: `'{"dev":"<base64_private_key>","other":"<base64_private_key>"}'`.
  - each node picks key by `ssh_key_ref`.
- Backward compatibility still works:
  - `ANSIBLE_SSH_PRIVATE_KEY_B64`,
  - `ANSIBLE_SSH_PRIVATE_KEY`,
  - `ANSIBLE_SSH_PRIVATE_KEY_FILE`.

If keys are missing, deploy workflow fails fast before Ansible.

## 4. Verify

```bash
docker node ls
docker node inspect <node> --format '{{ json .Spec.Labels }}'
wg show wg0
```

## Emergency fallback

`scripts/legacy/add-node.sh` is kept only for emergency/manual recovery.
