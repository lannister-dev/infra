# Infra Nodes (Non-VPN)

`terraform/infra-nodes` manages manager/worker nodes for core stacks
(Traefik, Harbor, bots, monitoring).

Source of truth: `terraform/infra-nodes/catalog.auto.tfvars`.

## Modes

1. Manual catalog via `infra_nodes`.
2. Existing Timeweb servers via API lookup in `timeweb_infra_nodes`.
3. Timeweb compute create/destroy via `timeweb_provisioned_infra_nodes`.

`timeweb_provisioned_infra_nodes` is implemented with provider resource `twc_server`.

## Example: Timeweb compute node

```hcl
timeweb_compute_enabled = true

timeweb_provisioned_infra_nodes = {
  "mgr-a" = {
    os_id             = 79
    location          = "ru-1"
    availability_zone = "spb-3"
    preset_type       = "premium"
    cpu               = 2
    ram               = 4096
    disk              = 40960
    ssh_keys_ids      = [12345]
    role              = "manager"
    kind              = "prod"
    enabled           = true
    ssh_key_ref       = "default"
    region            = "spb-3"
  }
}
```

Use `preset_id` when you already know the fixed preset to deploy.
Use `location + cpu + ram + disk` when you need a like-for-like replacement of
an existing custom-configured Timeweb VM in another availability zone.

## Run

```bash
set -a
source .env
set +a

terraform -chdir=terraform/infra-nodes init -input=false -backend-config="$(pwd)/terraform/backends/infra-nodes.hcl"
terraform -chdir=terraform/infra-nodes plan -input=false
terraform -chdir=terraform/infra-nodes apply -input=false
```

## Credentials

Use `.env`/CI secrets:
- `TIMEWEB_API_TOKEN`
- optional: `TIMEWEB_API_URL`, `TIMEWEB_AUTH_HEADER`, `TIMEWEB_AUTH_SCHEME`, `TIMEWEB_ENDPOINT_TEMPLATE`
- `ANSIBLE_SSH_KEYS_DIR` or `ANSIBLE_SSH_PRIVATE_KEY_FILE` for infra node bootstrap

## Lifecycle semantics

- `enabled = false`: node excluded from desired cluster; VPS still exists.
- Remove key from `timeweb_provisioned_infra_nodes`: VPS is destroyed.
