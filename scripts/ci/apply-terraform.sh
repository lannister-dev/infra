#!/usr/bin/env bash
# ---------------------------------------------------------------------
# Terraform init → plan → apply for every IaC root.
#
# Expected environment (sourced by caller from INFRA_ENV_PROD):
#   TF_STATE_BUCKET, TF_STATE_REGION, TF_STATE_KEY_PREFIX  (required)
#   TF_STATE_ENDPOINT, TF_STATE_ACCESS_KEY, …              (optional)
#   TF_PROVIDER_MIRROR_URL | TF_CLI_CONFIG_CONTENT[_B64]   (optional)
#   APPLY_INFRA_NODES=true|false                            (optional)
#
# Outputs (written to GITHUB_ENV when running in Actions):
#   PROMETHEUS_CONFIG_NAME, GRAFANA_INI_CONFIG_NAME, …
# ---------------------------------------------------------------------
set -Eeo pipefail
set -u

: "${TF_STATE_BUCKET:?TF_STATE_BUCKET is required}"
: "${TF_STATE_REGION:?TF_STATE_REGION is required}"
: "${TF_STATE_KEY_PREFIX:?TF_STATE_KEY_PREFIX is required}"

GITHUB_ENV="${GITHUB_ENV:-/dev/null}"

# ----- provider mirror --------------------------------------------------
# Sets _TF_MIRROR_CFG_TMP (path to temp file) for cleanup by caller.
_TF_MIRROR_CFG_TMP=""

setup_provider_mirror() {
  local cfg=""

  if [ -n "${TF_CLI_CONFIG_CONTENT_B64:-}" ]; then
    cfg="$(mktemp)"
    printf '%s' "${TF_CLI_CONFIG_CONTENT_B64}" | base64 -d > "${cfg}"
  elif [ -n "${TF_CLI_CONFIG_CONTENT:-}" ]; then
    cfg="$(mktemp)"
    printf '%s\n' "${TF_CLI_CONFIG_CONTENT}" > "${cfg}"
  elif [ -z "${TF_CLI_CONFIG_FILE:-}" ] && [ -n "${TF_PROVIDER_MIRROR_URL:-}" ]; then
    cfg="$(mktemp)"
    printf 'provider_installation {\n  network_mirror {\n    url = "%s"\n    include = ["registry.terraform.io/*/*"]\n  }\n  direct {\n    exclude = ["registry.terraform.io/*/*"]\n  }\n}\n' \
      "${TF_PROVIDER_MIRROR_URL}" > "${cfg}"
  fi

  if [ -n "${cfg}" ]; then
    chmod 600 "${cfg}"
    export TF_CLI_CONFIG_FILE="${cfg}"
    export TOFU_CONFIG_FILE="${cfg}"
    _TF_MIRROR_CFG_TMP="${cfg}"
  fi
}

# ----- S3 backend config ------------------------------------------------
write_backend_config() {
  local state_key="$1" out="$2"
  {
    echo "bucket = \"${TF_STATE_BUCKET}\""
    echo "key    = \"${TF_STATE_KEY_PREFIX}/${state_key}\""
    echo "region = \"${TF_STATE_REGION}\""

    [ -z "${TF_STATE_DYNAMODB_TABLE:-}" ] \
      || echo "dynamodb_table = \"${TF_STATE_DYNAMODB_TABLE}\""

    if [ -n "${TF_STATE_ENDPOINT:-}" ]; then
      echo "endpoints                 = { s3 = \"${TF_STATE_ENDPOINT}\" }"
      echo "force_path_style          = ${TF_STATE_FORCE_PATH_STYLE:-true}"
      echo "skip_credentials_validation = true"
      echo "skip_region_validation      = true"
      echo "skip_requesting_account_id  = true"
      echo "skip_metadata_api_check     = true"
      echo "skip_s3_checksum            = true"
    fi

    [ -z "${TF_STATE_ACCESS_KEY:-}" ] \
      || echo "access_key = \"${TF_STATE_ACCESS_KEY}\""
    [ -z "${TF_STATE_SECRET_KEY:-}" ] \
      || echo "secret_key = \"${TF_STATE_SECRET_KEY}\""
  } > "${out}"
  chmod 600 "${out}"
}

# ----- export foundation config names -----------------------------------
export_config_names() {
  terraform -chdir="terraform/foundation" output -json docker_config_names \
    | python3 -c '
import sys, json
m = json.load(sys.stdin)
for env_name, key in {
    "PROMETHEUS_CONFIG_NAME":          "prometheus",
    "GRAFANA_INI_CONFIG_NAME":         "grafana_ini",
    "GRAFANA_DATASOURCES_CONFIG_NAME": "grafana_datasources",
    "GRAFANA_DASHBOARDS_CONFIG_NAME":  "grafana_dashboards",
    "XRAY_CONFIG_NAME":                "xray",
    "XRAY_CONFIG_DEV_NAME":            "xray_dev",
    "VPN_FALLBACK_INDEX_CONFIG_NAME":  "vpn_fallback_index",
    "VPN_FALLBACK_NGINX_CONFIG_NAME":  "vpn_fallback_nginx",
}.items():
    print("{}={}".format(env_name, m.get(key, "")))
' >> "${GITHUB_ENV}"
}

# ----- main --------------------------------------------------------------
main() {
  # Convert IAC_TFVAR_* → TF_VAR_*
  local script_dir
  script_dir="$(cd "$(dirname "$0")/.." && pwd)"
  # shellcheck source=scripts/core/prepare-terraform-env.sh
  source "${script_dir}/core/prepare-terraform-env.sh"

  setup_provider_mirror

  local roots=(foundation nodes)
  [ "${APPLY_INFRA_NODES:-false}" != "true" ] || roots+=(infra-nodes)

  for root in "${roots[@]}"; do
    echo "::group::terraform/${root}"

    local backend_file
    backend_file="$(mktemp)"
    write_backend_config "${root}.tfstate" "${backend_file}"

    unset TF_VAR_inventory_output_path
    case "${root}" in
      nodes)       export TF_VAR_inventory_output_path="${INVENTORY_OUTPUT_PATH:-}" ;;
      infra-nodes) export TF_VAR_inventory_output_path="${INFRA_NODES_OUTPUT_PATH:-}" ;;
    esac

    terraform -chdir="terraform/${root}" init  -input=false -backend-config="${backend_file}"
    terraform -chdir="terraform/${root}" plan  -input=false -out=tfplan
    terraform -chdir="terraform/${root}" apply -input=false -auto-approve tfplan

    [ "${root}" != "foundation" ] || export_config_names

    rm -f "${backend_file}" "terraform/${root}/tfplan"
    echo "::endgroup::"
  done

  [ -z "${_TF_MIRROR_CFG_TMP}" ] || rm -f "${_TF_MIRROR_CFG_TMP}"
}

main "$@"
