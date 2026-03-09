# Data Prod Migration (Legacy -> Managed Stack)

Goal: migrate from legacy manually created PostgreSQL/Redis to managed swarm stack `data-prod`
without immediate downtime.

## 1. Prepare managed stack

In `INFRA_ENV_PROD`:

```bash
DEPLOY_DATA_PROD_STACK=true
DATA_PROD_POSTGRES_DB=vpn_control
DATA_PROD_POSTGRES_USER=vpn_prod_user
DATA_PROD_POSTGRES_PASSWORD=replace_with_strong_password
DATA_PROD_REDIS_PASSWORD=replace_with_strong_password
```

Deploy:

```bash
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/deploy-stacks.yml
```

Managed endpoints in `vpn-net`:
- Postgres: `postgres-prod:5432`
- Redis: `redis-prod:6379`

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
- Redis password = `DATA_PROD_REDIS_PASSWORD`

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
