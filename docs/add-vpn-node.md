# Add VPN Node

Primary flow is fully declarative.

## 1. Update topology

Edit `terraform/nodes/catalog.auto.tfvars`:
- `vpn_nodes` for manual IP,
- or `hostvds_vpn_nodes` for existing server IDs,
- or `hostvds_provisioned_vpn_nodes` for Terraform-managed compute.

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

## 4. Verify

```bash
docker node ls
docker node inspect <node> --format '{{ json .Spec.Labels }}'
wg show wg0
```

## Emergency fallback

`scripts/legacy/add-node.sh` is kept only for emergency/manual recovery.
