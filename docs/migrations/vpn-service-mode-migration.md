# VPN Service Mode Migration (one-time)

## Why

Docker Swarm does not allow in-place service mode change:

- `replicated -> global`
- `global -> replicated`

If `deploy.mode` changes for existing service, `docker stack deploy` fails with:
`service mode change is not allowed`.

## Commands

Check current mode:

```bash
docker service inspect vpn_xray --format '{{if .Spec.Mode.Global}}global{{else}}replicated{{end}}'
docker service inspect vpn_node-agent --format '{{if .Spec.Mode.Global}}global{{else}}replicated{{end}}'
docker service inspect vpn_vpn-fallback --format '{{if .Spec.Mode.Global}}global{{else}}replicated{{end}}'
```

Expected:

- `vpn_xray` -> `global`
- `vpn_node-agent` -> `global`
- `vpn_vpn-fallback` -> `replicated`

If different, recreate only those services:

```bash
docker service rm vpn_xray
docker service rm vpn_node-agent
docker service rm vpn_vpn-fallback
```

Then run normal declarative cycle:

```bash
set -a
source .env
set +a

terraform -chdir=terraform/foundation apply
terraform -chdir=terraform/nodes apply

export REPO_ROOT="$(pwd)"
export ANSIBLE_CONFIG="$(pwd)/ansible/ansible.cfg"
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/reconcile-vpn-nodes.yml
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/deploy-stacks.yml
```
