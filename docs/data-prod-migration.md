# Data Prod Migration (Legacy -> Managed Stack)

Goal: migrate production PostgreSQL/Redis data without immediate downtime.

This document covers two cases:
- legacy external services -> managed swarm stack `data-prod`;
- managed `data-prod` migration to another prod manager node with data preserved.

## 1. Prepare managed stack

In `INFRA_ENV_PROD`:

```bash
DEPLOY_DATA_PROD_STACK=true
PROD_POSTGRES_DB=vpn_control
PROD_POSTGRES_USER=vpn_prod_user
PROD_POSTGRES_PASSWORD=<strong_password>
PROD_REDIS_PASSWORD=<strong_password>
```

Deploy:

```bash
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/deploy-stacks.yml
```

For a data-only rollout, use:

```bash
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/deploy-data-stacks.yml
```

GitHub Actions alternative:

- workflow `Infra Data Deploy`
- `confirm_apply=PROD-DATA`

Managed endpoints in `data-prod-net`:
- Postgres: `postgres-prod:5432`
- Redis: `redis-prod:6379`

If you need to pin `data-prod` to a specific prod manager during migration,
set:

```bash
DATA_PROD_PLACEMENT_CONSTRAINT=node.hostname == <target_manager_hostname>
```

Then redeploy `data-prod` before restore/cutover.

## 2. Create backups from legacy services

PostgreSQL:

```bash
pg_dump -Fc -h <legacy_pg_host> -p 5432 -U <legacy_pg_user> <legacy_pg_db> > legacy_pg.dump
```

Redis:

```bash
redis-cli -h <legacy_redis_host> -p 6379 -a '<legacy_redis_password>' --rdb legacy_redis.rdb
```

## 3. Restore into managed stack

PostgreSQL restore:

```bash
pg_restore -h <manager_or_service_access> -p 5432 -U vpn_prod_user -d vpn_control --clean --if-exists legacy_pg.dump
```

Redis restore:
- stop writes to legacy redis;
- replace managed Redis dataset with `legacy_redis.rdb`;
- restart `data-prod_redis`.

## 4. Cutover

Update control-plane/probe runtime env to:
- Postgres host `postgres-prod`, port `5432`
- Redis host `redis-prod`, port `6379`
- Redis password = `PROD_REDIS_PASSWORD`

Deploy updated services.

## 5. Validate

- API health checks pass.
- write/read path works for DB and Redis.
- background jobs and probe processing work.
- no auth or connection errors in logs.

## 6. Rollback plan

If validation fails:
- switch env back to legacy DB/Redis endpoints;
- redeploy affected services;
- keep managed stack running for investigation.

## Managed data-prod node migration

If `data-prod` is already the active production datastore, do not rely on Swarm
rescheduling. Both Postgres and Redis use `local` volumes, so moving the service
to another manager without a data copy will start with empty storage.

Recommended sequence:

1. Provision and bootstrap the new prod manager.
2. Set `DATA_PROD_PLACEMENT_CONSTRAINT=node.hostname == <new_manager_hostname>`.
3. Deploy `data-prod` on the new node.
4. Stop writes or enable maintenance mode on control-plane workloads.
5. Create a fresh PostgreSQL dump and Redis RDB snapshot from the current prod node.
6. Restore those datasets into the new `data-prod` services.
7. Validate app read/write path against `postgres-prod` and `redis-prod`.
8. Only then drain/decommission the old manager node.
