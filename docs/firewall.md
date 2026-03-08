# Firewall Baseline (Dev + Prod)

This repository now includes an explicit firewall reconciliation playbook:

- `ansible/playbooks/reconcile-firewall.yml`

It applies a host-level UFW baseline to all **enabled infra nodes** from
`ansible/inventory/generated/infra_nodes.yml`.

## Why

- Keep `dev` and `prod` consistent in security posture.
- Restrict NATS client ingress (`4222/tcp`) to known CIDRs.
- Keep Swarm control/data ports open only between cluster nodes.

## Required env before run

```bash
export FIREWALL_ENFORCE=true
export FIREWALL_ADMIN_CIDRS="X.X.X.X/32,Y.Y.Y.Y/32"
export FIREWALL_NATS_CLIENT_CIDRS="A.A.A.A/32,B.B.B.B/32"
```

Optional toggles:

```bash
export FIREWALL_OPEN_HTTP=true
export FIREWALL_OPEN_HTTPS=true
export FIREWALL_OPEN_NATS=true
export FIREWALL_OPEN_SWARM_PORTS=true
```

## Applied rules (baseline)

- default: `deny incoming`, `allow outgoing`
- `22/tcp` from `FIREWALL_ADMIN_CIDRS`
- `80/tcp` + `443/tcp` on manager nodes (Traefik)
- `4222/tcp` on manager nodes from `FIREWALL_NATS_CLIENT_CIDRS`
- Swarm ports from infra-node peer CIDRs:
  - `2377/tcp`
  - `7946/tcp+udp`
  - `4789/udp`

## Run

```bash
set -a
source .env
set +a

export REPO_ROOT="$(pwd)"
export ANSIBLE_CONFIG="$(pwd)/ansible/ansible.cfg"

ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/reconcile-firewall.yml
```

## Safety notes

- Do not enable without valid admin CIDRs, or you risk SSH lockout.
- Roll out in maintenance window for the first run.
- Validate from outside after apply:
  - SSH from admin source works.
  - `80/443` reachable where expected.
  - `4222` reachable only from allowed agent/control-plane CIDRs.
