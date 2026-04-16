# Terraform Infrastructure

Terraform manages the K3s infra-node catalog and Yandex Cloud VPN nodes. Non-YC VPN nodes
are provisioned by `vpn-control-api` (admin UI → installer one-liner) and are not owned
by Terraform.

## Root modules

- `terraform/infra-nodes`: non-VPN infra nodes (Timeweb + manual).
- `terraform/yandex-vpn`: Yandex Cloud VPN entry nodes (adopt existing + create new).

Each root has its own remote state key:
- `infra-nodes.tfstate`
- `yandex-vpn.tfstate`

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

- `terraform/infra-nodes/catalog.auto.tfvars`
- `terraform/infra-nodes/catalog.dev.tfvars` (dev workflow var-file)
- `terraform/yandex-vpn/catalog.auto.tfvars`
- `terraform/yandex-vpn/catalog.dev.tfvars` (dev workflow var-file)

Credentials/tokens remain in local `.env` or CI secrets and are passed as `TF_VAR_*`.

CI convention for variables:
- if your environment supports lowercase names, you can define `TF_VAR_<terraform_variable_name>` directly.
- for uppercase-only environments, use `IAC_TFVAR_<UPPER_SNAKE_NAME>`; it is auto-converted to `TF_VAR_<lower_snake_name>`.
- conversion is done by `scripts/core/prepare-terraform-env.sh`.

## Modes

`terraform/yandex-vpn` supports two per-node modes inside `yandex_vpn_nodes`:
- `adopt` — take over an existing VM + reserved IP + SG by ID (with `prevent_destroy = true`).
- `create` — provision a fresh VM + IP + SG from the given spec; put the installer
  one-liner into `user_data`.

`terraform/infra-nodes` supports:
- Manual catalog: `infra_nodes`
- Timeweb API lookup: `timeweb_infra_nodes`
- Timeweb compute create/destroy: `timeweb_provisioned_infra_nodes`

## Required runtime credentials

Yandex Cloud (`terraform/yandex-vpn`):
- preferred: `YC_SERVICE_ACCOUNT_KEY_FILE` or `TF_VAR_yandex_service_account_key_file`
- CI/Vault-friendly option: `YC_SERVICE_ACCOUNT_KEY_B64` (workflow decodes into a temp
  file and exports `TF_VAR_yandex_service_account_key_file`)
- fallback for short-lived manual runs: `YC_TOKEN` or `TF_VAR_yandex_token`
- `YC_CLOUD_ID` or `TF_VAR_yandex_cloud_id`
- `YC_FOLDER_ID` or `TF_VAR_yandex_folder_id`
- optional: `TF_VAR_yandex_zone`

Timeweb (`terraform/infra-nodes`):
- `TIMEWEB_API_TOKEN`
- optional overrides: `TIMEWEB_API_URL`, `TIMEWEB_AUTH_HEADER`, `TIMEWEB_AUTH_SCHEME`, `TIMEWEB_ENDPOINT_TEMPLATE`

## Local run

```bash
set -a
source .env
set +a

terraform -chdir=terraform/infra-nodes init -input=false -backend-config="$(pwd)/terraform/backends/infra-nodes.hcl"
terraform -chdir=terraform/infra-nodes apply -input=false

terraform -chdir=terraform/yandex-vpn init -input=false -backend-config="$(pwd)/terraform/backends/yandex-vpn.hcl"
terraform -chdir=terraform/yandex-vpn apply -input=false
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
- Optional inputs: `apply_infra_nodes=true`, `apply_yandex_vpn=true`.

Topology for CI comes from repository tfvars.
Runtime secrets are read from Vault:
- prod infra env: `kv/infra/prod#config`
- dev infra env: `kv/infra/dev#config`

## K8s deployment

After Terraform provisions servers, K3s cluster management and workload
deployment is handled via Helm charts in `k8s/`. See `k8s/Makefile` for targets.
