# Add VPN Node

Primary flow is fully declarative.

## 1. Update topology

Edit `terraform/nodes/catalog.auto.tfvars`:
- `vpn_nodes` for manual IP,
- or `provider_api_vpn_nodes` for existing server IDs (recommended),
- or `provider_compute_vpn_nodes` for Terraform-managed compute (recommended for frequent rotation).
- or `yandex_whitelist_entry_nodes` for already existing Yandex Cloud whitelist entry nodes that must be imported without recreate.
- set `ssh_key_ref` per node (example: `dev`, `hostvds`, `timeweb`).

Important runtime rule:
- `traffic_role=standard` nodes run the regular backend stacks (`vpn_xray`, `vpn_node-agent`).
- `traffic_role=whitelist_entry` nodes join Swarm but do not run backend stacks; they run the dedicated `vpn-whitelist-entry` relay stack instead.

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

If you are enabling a whitelist entry node, set relay upstream before deploy:

```bash
export VPN_WHITELIST_ENTRY_UPSTREAM_HOST=<backend_ip_or_dns>
export VPN_WHITELIST_ENTRY_UPSTREAM_PORT=443
```

## SSH requirements

- For HostVDS Ubuntu images in this project, use `ssh_user = "root"` in node catalog.
- Server must be created with a known key pair (for example `dev`).
- CI secret `INFRA_ENV_PROD` should provide `ANSIBLE_SSH_KEYS_B64_JSON`:
  - JSON object: `'{"dev":"<base64_private_key>","yc":"<base64_private_key>","other":"<base64_private_key>"}'`.
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

For whitelist entry nodes also verify:

```bash
docker service ps vpn-whitelist-entry_relay
docker service ps vpn_xray
docker service ps vpn_node-agent
```

## Emergency fallback

`scripts/legacy/add-node.sh` is kept only for emergency/manual recovery.
