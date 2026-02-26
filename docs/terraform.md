# Terraform Infrastructure

Terraform is the source of truth for infrastructure state in this repository.

## Root modules

- `terraform/foundation`: Swarm foundation (networks, volumes, Docker configs).
- `terraform/nodes`: provider-agnostic VPN node catalog (provider modules underneath).
- `terraform/infra-nodes`: non-VPN infra nodes (Timeweb).

Each root has its own remote state key:
- `foundation.tfstate`
- `nodes.tfstate`
- `infra-nodes.tfstate`

## Topology source of truth

Topology is declared in versioned tfvars files:

- `terraform/nodes/catalog.auto.tfvars`
- `terraform/infra-nodes/catalog.auto.tfvars`

Do not keep topology in JSON env variables anymore.

Credentials/tokens remain in local `.env` or CI secrets and are passed as `TF_VAR_*`.

CI convention for variables:
- preferred: define `TF_VAR_<terraform_variable_name>` directly in secret env.
- alias supported: `IAC_TFVAR_<UPPER_SNAKE_NAME>` (auto-converted to `TF_VAR_<lower_snake_name>`).
- conversion is done by `scripts/core/prepare-terraform-env.sh`.

This keeps workflow provider-agnostic: adding/removing providers does not require
editing workflow `export` lists.

## Provider modes

`terraform/nodes` supports:
- Manual catalog: `vpn_nodes`
- Provider API lookup for existing servers: `provider_api_vpn_nodes`
- Provider compute create/destroy: `provider_compute_vpn_nodes`

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

Timeweb for `terraform/infra-nodes` provider modes:
- `TIMEWEB_API_TOKEN`
- optional overrides: `TIMEWEB_API_URL`, `TIMEWEB_AUTH_HEADER`, `TIMEWEB_AUTH_SCHEME`, `TIMEWEB_ENDPOINT_TEMPLATE`

## Local run

Linux/macOS:

```bash
set -a
source .env
set +a

terraform -chdir=terraform/foundation init -input=false -backend-config="$(pwd)/terraform/backends/foundation.hcl"
terraform -chdir=terraform/foundation apply -input=false

terraform -chdir=terraform/nodes init -input=false -backend-config="$(pwd)/terraform/backends/nodes.hcl"
terraform -chdir=terraform/nodes apply -input=false

terraform -chdir=terraform/infra-nodes init -input=false -backend-config="$(pwd)/terraform/backends/infra-nodes.hcl"
terraform -chdir=terraform/infra-nodes apply -input=false
```

Windows PowerShell:

```powershell
Get-Content .\.env | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
  $pair = $_ -split '=', 2
  if ($pair.Length -eq 2) {
    [Environment]::SetEnvironmentVariable($pair[0], $pair[1], 'Process')
  }
}

terraform -chdir=terraform/foundation init -input=false -backend-config="$PWD/terraform/backends/foundation.hcl"
terraform -chdir=terraform/foundation apply -input=false

terraform -chdir=terraform/nodes init -input=false -backend-config="$PWD/terraform/backends/nodes.hcl"
terraform -chdir=terraform/nodes apply -input=false

terraform -chdir=terraform/infra-nodes init -input=false -backend-config="$PWD/terraform/backends/infra-nodes.hcl"
terraform -chdir=terraform/infra-nodes apply -input=false
```

## Tooling

Use preinstalled `terraform` (or `tofu`) on the target runner/host.
In restricted regions, configure provider mirror via `TF_PROVIDER_MIRROR_URL`
or full CLI config vars (`TF_CLI_CONFIG_CONTENT*`) in deploy environment.

If IDE shows `Unknown resource` or `Unresolved reference` for provider resources
(`twc_server`, `openstack_compute_instance_v2`), run init in each root so provider
schemas are downloaded.

## CI

Workflows:
- `.github/workflows/infra-ci.yml`: checks on `pull_request`/`push`.
- `.github/workflows/infra-deploy.yml`: production deploy via `workflow_dispatch`.
- `.github/workflows/infra-checks-reusable.yml`: shared checks job.

Deploy gate:
- `workflow_dispatch` + `confirm_apply=APPLY`.
- Optional input `apply_infra_nodes=true`: also applies `terraform/infra-nodes`.

Topology for CI comes from repository tfvars; secrets come from `INFRA_ENV_PROD`.

Recommended `INFRA_ENV_PROD` style:

```bash
TF_STATE_BUCKET=...
TF_STATE_REGION=...
TF_STATE_KEY_PREFIX=...

# Provider mirror in restricted regions (recommended)
TF_PROVIDER_MIRROR_URL=https://terraform-mirror.yandexcloud.net/

TF_VAR_vpn_domain=example.com
TF_VAR_vpn_ws_path=/api/v1/stream
TF_VAR_vpn_xhttp_path=/api/v1/mobile

# optional generic alias style (auto-converted)
# IAC_TFVAR_HOSTVDS_OS_AUTH_URL=https://os-api.hostvds.com/identity
# IAC_TFVAR_HOSTVDS_OS_USERNAME=...

# Ansible SSH keys for reconcile/deploy (required for node bootstrap)
# Recommended (multi-key): map key refs to base64 private keys.
# Nodes select key via ssh_key_ref in terraform/nodes/catalog.auto.tfvars.
# ANSIBLE_SSH_KEYS_B64_JSON='{"dev":"LS0tLS1CRUdJTi...","backup":"LS0tLS1CRUdJTi..."}'
#
# Backward-compatible single-key options:
# ANSIBLE_SSH_PRIVATE_KEY_B64=LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K...
# ANSIBLE_SSH_PRIVATE_KEY=-----BEGIN OPENSSH PRIVATE KEY-----...
# ANSIBLE_SSH_PRIVATE_KEY_FILE=/home/github-runner/.ssh/dev
```

Mirror behavior in deploy workflow:
- if `TF_CLI_CONFIG_CONTENT_B64` is set, it is used as full Terraform/OpenTofu CLI config;
- else if `TF_CLI_CONFIG_CONTENT` is set, it is used as full config;
- else if `TF_PROVIDER_MIRROR_URL` is set, workflow generates `provider_installation` config
  with mirror for `registry.terraform.io/*/*` and direct fallback for non-registry providers
  (for example, `tf.timeweb.cloud`).

Full example template:
- `docs/infra-env-prod.example`
