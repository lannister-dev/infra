# Data Dev Stack (Postgres + Redis)

Optional managed dev data stack is defined in:

- `docker/stacks/data-dev.yml`

It deploys:
- `data-dev_postgres` (PostgreSQL)
- `data-dev_redis` (Redis)

Placement constraints:
- `node.role == manager`
- `node.labels.kind == dev`

## Enable

Set in `INFRA_ENV_DEV`:

```bash
DEPLOY_DATA_DEV_STACK=true
DEV_POSTGRES_PASSWORD=<strong_password>
DEV_REDIS_PASSWORD=<strong_password>
```

Recommended deployment path:

- GitHub Actions workflow `Infra Data Deploy Dev`
- or `ansible-playbook -i ansible/inventory/development.ini ansible/playbooks/deploy-data-stacks.yml`

Optional overrides:

```bash
POSTGRES_IMAGE_TAG=16-alpine
REDIS_IMAGE_TAG=7-alpine
DEV_POSTGRES_DB=vpn_control_dev
DEV_POSTGRES_USER=vpn_dev_user
```

## Secrets

Playbook auto-creates swarm secrets when missing:
- `data_dev_postgres_password`
- `data_dev_redis_password`

## Service endpoints (inside `data-dev-net`)

- Postgres: `postgres-dev:5432`
- Redis: `redis-dev:6379`

Use these endpoints from services attached to `data-dev-net`.
Dev data services are intentionally isolated from `vpn-net`.
