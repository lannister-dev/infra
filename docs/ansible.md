# Ansible Operations

Ansible's role is now scoped to K3s cluster bootstrap on infra nodes. Node-agent and xray
deployment on VPN nodes is handled by `vpn-control-api` (admin UI installer + K3s
join) and the cluster-level Helm charts in `k8s/`.

## Playbooks

- `ansible/playbooks/setup-k3s-server.yml`
  - installs and configures K3s server on the `k3s_servers` group
  - fetches kubeconfig locally
  - disables embedded Traefik

## Roles

- `ansible/roles/k3s-server`
- `ansible/roles/k3s-agent`

## Inputs

Inventory is declared statically:
- `ansible/inventory/production.ini`
- `ansible/inventory/development.ini`

There is no Terraform-generated VPN inventory anymore; non-YC VPN nodes register
themselves with `vpn-control-api` on bootstrap and then with the K3s cluster via the
installer-provided join token.

## Run

```bash
set -a
source .env
set +a

export REPO_ROOT="$(pwd)"
export ANSIBLE_CONFIG="$(pwd)/ansible/ansible.cfg"

ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/setup-k3s-server.yml
```

The production `.github/workflows/k3s-setup.yml` workflow does the same from CI, using
`ANSIBLE_SSH_KEYS_B64_JSON` (or `ANSIBLE_SSH_PRIVATE_KEY_B64`) as the key source,
materialized by `scripts/core/render-ansible-ssh-keys.py`.

## SSH host keys

`ansible.cfg` uses strict host key checking.
Keep target host keys in known_hosts on the runner/manager.
