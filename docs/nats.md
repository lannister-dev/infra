# NATS (Swarm Stack)

This repository includes optional shared `nats` stack deployment for node agents and control plane components.
Recommended layout: a single NATS instance runs on the dev manager node and is shared by both prod and dev channels.

## What gets deployed

- `nats_nats` (NATS Server with JetStream + persistent local volume)
- `nats_nats-exporter` (Prometheus metrics exporter)

Placement constraints:
- `node.role == manager`
- `node.labels.kind == dev`

NATS client traffic (`4222/tcp`) is exposed via Traefik TCP entrypoint `nats`.
NATS monitoring endpoint (`8222`) is exposed via Traefik HTTPS route with basic auth.

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

From services attached to `vpn-net` or `vpn-dev-net`:
- `nats://<token>@nats:4222` (network alias)

From external node agents / control-plane clients:
- `nats://<token>@nats.lannister-dev.ru:4222`

The stack is attached to both overlay networks so prod and dev node agents can use the same internal alias while the NATS task itself remains pinned to the dev manager.

For monitoring:
- exporter metrics: `nats_nats-exporter:7777/metrics` (auto-scraped via existing Prometheus Swarm discovery labels)
- web monitor via Traefik: `https://nats.lannister-dev.ru/` (basic auth required)

## Troubleshooting

`Authorization Violation` in node-agent logs usually means NATS credentials mismatch:
- `NATS_SERVER` has no token (`nats://host:4222` instead of `nats://<token>@host:4222`).
- token in `NATS_SERVER` differs from deployed `NATS_AUTH_TOKEN`.
- wrong endpoint (`nats:4222` vs external domain) for current network path.

`Connection reset by peer` right after auth errors is expected: NATS closes unauthorized connections.
