# Terraform Infrastructure

Terraform manages VPS server provisioning for the K3s cluster.

## Root modules

- `terraform/nodes`: provider-agnostic VPN node catalog (provider modules underneath).
- `terraform/infra-nodes`: non-VPN infra nodes (Timeweb).

Each root has its own remote state key:
- `nodes.tfstate`
- `infra-nodes.tfstate`

## State locking

State locking prevents concurrent `terraform apply` runs from corrupting state.
Set `TF_STATE_DYNAMODB_TABLE` (e.g. `terraform-locks`) in your environment or
backend `.hcl` file. The CI script (`scripts/ci/apply-terraform.sh`) writes
`dynamodb_table` into the generated backend config automatically when the
variable is present.

For AWS S3 backends, create a DynamoDB table with a `LockID` string partition
key. For S3-compatible stores (Yandex Object Storage, MinIO), check provider
docs for lock table support.

## Topology source of truth

Topology is declared in versioned tfvars files:

- `terraform/nodes/catalog.auto.tfvars`
- `terraform/infra-nodes/catalog.auto.tfvars`
- `terraform/nodes/catalog.dev.tfvars` (dev workflow var-file)
- `terraform/infra-nodes/catalog.dev.tfvars` (dev workflow var-file)

Do not keep topology in JSON env variables anymore.

Credentials/tokens remain in local `.env` or CI secrets and are passed as `TF_VAR_*`.

CI convention for variables:
- if your environment supports lowercase names, you can define `TF_VAR_<terraform_variable_name>` directly.
- for uppercase-only environments, use `IAC_TFVAR_<UPPER_SNAKE_NAME>`; it is auto-converted to `TF_VAR_<lower_snake_name>`.
- conversion is done by `scripts/core/prepare-terraform-env.sh`.

## Provider modes

`terraform/nodes` supports:
- Manual catalog: `vpn_nodes`
- Provider API lookup for existing servers: `provider_api_vpn_nodes`
- Provider compute create/destroy: `provider_compute_vpn_nodes`
- Yandex Cloud whitelist entry adoption: `yandex_whitelist_entry_nodes`

Legacy compatibility:
- `hostvds_vpn_nodes`
- `hostvds_provisioned_vpn_nodes`

`terraform/infra-nodes` supports:
- Manual catalog: `infra_nodes`
- Timeweb API lookup: `timeweb_infra_nodes`
- Timeweb compute create/destroy: `timeweb_provisioned_infra_nodes`

Provider extensibility contract:
- each provider module should return normalized node maps with the same fields
  (`public_ip`, `ssh_user`, `ssh_port`, `enabled`, `provider`, `region`, plus role/channel).
- template: `terraform/nodes/modules/provider-template/README.md`

Important semantics:
- `enabled = false` removes node from desired cluster state, but does not destroy VPS.
- VPS destroy is done by removing node entry from the corresponding `*_provisioned_*` map.

## Required runtime credentials

HostVDS (OpenStack) for `terraform/nodes` entries with `provider=hostvds`:
- `HOSTVDS_OS_AUTH_URL`
- `HOSTVDS_OS_USERNAME`
- `HOSTVDS_OS_PASSWORD`
- `HOSTVDS_OS_PROJECT_NAME`
- `HOSTVDS_OS_USER_DOMAIN_NAME` or `HOSTVDS_OS_USER_DOMAIN_ID`
- `HOSTVDS_OS_PROJECT_DOMAIN_NAME` or `HOSTVDS_OS_PROJECT_DOMAIN_ID`
- `HOSTVDS_OS_REGION_NAME`
- `HOSTVDS_OS_INTERFACE`

Yandex Cloud for `terraform/nodes` entries in `yandex_whitelist_entry_nodes`:
- preferred: `YC_SERVICE_ACCOUNT_KEY_FILE` or `TF_VAR_yandex_service_account_key_file`
- CI/Vault-friendly option: `YC_SERVICE_ACCOUNT_KEY_B64` (workflow decodes it into a temp file and exports `TF_VAR_yandex_service_account_key_file`)
- fallback for short-lived manual runs: `YC_TOKEN` or `TF_VAR_yandex_token`
- `YC_CLOUD_ID` or `TF_VAR_yandex_cloud_id`
- `YC_FOLDER_ID` or `TF_VAR_yandex_folder_id`
- optional: `TF_VAR_yandex_zone`

Timeweb for `terraform/infra-nodes` provider modes:
- `TIMEWEB_API_TOKEN`
- optional overrides: `TIMEWEB_API_URL`, `TIMEWEB_AUTH_HEADER`, `TIMEWEB_AUTH_SCHEME`, `TIMEWEB_ENDPOINT_TEMPLATE`

## Local run

```bash
set -a
source .env
set +a

terraform -chdir=terraform/nodes init -input=false -backend-config="$(pwd)/terraform/backends/nodes.hcl"
terraform -chdir=terraform/nodes apply -input=false

terraform -chdir=terraform/infra-nodes init -input=false -backend-config="$(pwd)/terraform/backends/infra-nodes.hcl"
terraform -chdir=terraform/infra-nodes apply -input=false
```

## Tooling

Deploy workflows install Terraform automatically using `TF_PROVIDER_MIRROR_URL`.
If it is set to Yandex provider mirror `https://terraform-mirror.yandexcloud.net/`,
deploy workflows download the Terraform binary from
`https://hashicorp-releases.yandexcloud.net/terraform`.
In restricted regions, configure provider mirror via `TF_PROVIDER_MIRROR_URL`
or full CLI config vars (`TF_CLI_CONFIG_CONTENT*`) in deploy environment.

## CI

Workflows:
- `.github/workflows/infra-ci.yml`: checks on `pull_request`/`push`.
- `.github/workflows/infra-deploy.yml`: production deploy via `workflow_dispatch`.
- `.github/workflows/infra-deploy-dev.yml`: development deploy via `workflow_dispatch`.
- `.github/workflows/infra-checks-reusable.yml`: shared checks job.

Deploy gate:
- `workflow_dispatch` + `confirm_apply=APPLY`.
- dev deploy gate: `workflow_dispatch` + `confirm_apply=DEV`.
- Optional input `apply_infra_nodes=true`: also applies `terraform/infra-nodes`.

Topology for CI comes from repository tfvars.
Runtime secrets are read from Vault:
- prod infra env: `kv/infra/prod#config`
- dev infra env: `kv/infra/dev#config`

## K8s deployment

After Terraform provisions VPS servers, K3s cluster management and workload
deployment is handled via Helm charts in `k8s/`. See `k8s/Makefile` for targets.
