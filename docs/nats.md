# NATS (Swarm Stack)

This repository includes optional `nats` stack deployment for development messaging between node agents and control plane components.

## What gets deployed

- `nats_nats` (NATS Server with JetStream + persistent local volume)
- `nats_nats-exporter` (Prometheus metrics exporter)

Placement constraints:
- `node.role == manager`
- `node.labels.kind == dev`

No public port is published directly. NATS monitoring endpoint (`8222`) is exposed via Traefik HTTPS route with basic auth.

## Enable deployment

NATS deploy is enabled by default. Optional toggle:

```bash
export DEPLOY_NATS_STACK=false
```

Set token in environment (`.env`) before deploy:

```bash
export NATS_AUTH_TOKEN='replace-with-strong-random-token'
```

Playbook auto-creates Swarm secret `nats_auth_token` if it is missing.

Then deploy as usual:

```bash
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/deploy-stacks.yml
```

## Connection endpoints

From services attached to `vpn-net`:
- `nats://<token>@nats:4222` (network alias)
- fallback: `nats://<token>@nats_nats:4222` (stack service name)

For monitoring:
- exporter metrics: `nats_nats-exporter:7777/metrics` (auto-scraped via existing Prometheus Swarm discovery labels)
- web monitor via Traefik: `https://nats.lannister-dev.ru/` (basic auth required)
