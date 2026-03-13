#!/usr/bin/env bash
# ---------------------------------------------------------------------
# Terraform init → plan → apply for every IaC root.
#
# Expected environment (sourced by caller from INFRA_ENV_PROD):
#   TF_STATE_BUCKET, TF_STATE_REGION, TF_STATE_KEY_PREFIX  (required)
#   TF_STATE_ENDPOINT, TF_STATE_ACCESS_KEY, …              (optional)
#   TF_PROVIDER_MIRROR_URL | TF_CLI_CONFIG_CONTENT[_B64]   (optional)
#   APPLY_FOUNDATION=true|false                            (optional)
#   APPLY_NODES=true|false                                 (optional)
#   APPLY_INFRA_NODES=true|false                            (optional)
#   FOUNDATION_TFVARS_FILE / NODES_TFVARS_FILE /
#   INFRA_NODES_TFVARS_FILE                                 (optional)
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
NODES_REPLACE_ARGS=()

FOUNDATION_TFVARS_FILE="${FOUNDATION_TFVARS_FILE:-}"
NODES_TFVARS_FILE="${NODES_TFVARS_FILE:-}"
INFRA_NODES_TFVARS_FILE="${INFRA_NODES_TFVARS_FILE:-}"

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

validate_tfvars_file() {
  local file_path="$1" root="$2"
  [ -n "${file_path}" ] || return 0
  if [ ! -f "${file_path}" ]; then
    echo "::error::Missing tfvars file for terraform/${root}: ${file_path}"
    exit 1
  fi
}

tf_state_has() {
  local root="$1"
  local addr="$2"
  terraform -chdir="terraform/${root}" state show "${addr}" >/dev/null 2>&1
}

# ----- export foundation config names -----------------------------------
export_config_names() {
  local config_names_json
  local exported_env_file
  config_names_json="$(terraform -chdir="terraform/foundation" output -json docker_config_names)"
  exported_env_file="$(mktemp)"

  printf '%s' "${config_names_json}" \
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
    "VAULT_CONFIG_NAME":               "vault",
}.items():
    print("{}={}".format(env_name, m.get(key, "")))
' > "${exported_env_file}"

  cat "${exported_env_file}" >> "${GITHUB_ENV}"
  set -a
  # shellcheck disable=SC1090
  source "${exported_env_file}"
  set +a
  rm -f "${exported_env_file}"

  printf '%s' "${config_names_json}" \
    | python3 -c '
import sys, json
m = json.load(sys.stdin)
for notice_name, key in {
    "foundation.xray": "xray",
    "foundation.xray_dev": "xray_dev",
    "foundation.prometheus": "prometheus",
    "foundation.grafana_ini": "grafana_ini",
}.items():
    print("::notice::{}={}".format(notice_name, m.get(key, "")))
'
}

log_foundation_input_fingerprints() {
  python3 - <<'PY'
import hashlib
import os

def short_hash(value: str) -> str:
    if not value:
        return ""
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]

fields = {
    "foundation.var.vpn_domain": os.getenv("TF_VAR_vpn_domain", ""),
    "foundation.var.vpn_ws_path": os.getenv("TF_VAR_vpn_ws_path", ""),
    "foundation.var.vpn_xhttp_path": os.getenv("TF_VAR_vpn_xhttp_path", ""),
    "foundation.var.vpn_reality_server_name": os.getenv("TF_VAR_vpn_reality_server_name", ""),
    "foundation.var.vpn_reality_dest_host": os.getenv("TF_VAR_vpn_reality_dest_host", ""),
    "foundation.var.vpn_dev_domain": os.getenv("TF_VAR_vpn_dev_domain", ""),
    "foundation.var.vpn_dev_ws_path": os.getenv("TF_VAR_vpn_dev_ws_path", ""),
    "foundation.var.vpn_dev_xhttp_path": os.getenv("TF_VAR_vpn_dev_xhttp_path", ""),
    "foundation.var.vpn_dev_reality_server_name": os.getenv("TF_VAR_vpn_dev_reality_server_name", ""),
    "foundation.var.vpn_dev_reality_dest_host": os.getenv("TF_VAR_vpn_dev_reality_dest_host", ""),
    "foundation.var.enable_vpn_dev_stack": os.getenv("TF_VAR_enable_vpn_dev_stack", ""),
}
secret_fields = {
    "foundation.var.vpn_reality_private_key.sha256_12": os.getenv("TF_VAR_vpn_reality_private_key", ""),
    "foundation.var.vpn_reality_short_id.sha256_12": os.getenv("TF_VAR_vpn_reality_short_id", ""),
    "foundation.var.vpn_dev_reality_private_key.sha256_12": os.getenv("TF_VAR_vpn_dev_reality_private_key", ""),
    "foundation.var.vpn_dev_reality_short_id.sha256_12": os.getenv("TF_VAR_vpn_dev_reality_short_id", ""),
}
for name, value in fields.items():
    print(f"::notice::{name}={value}")
for name, value in secret_fields.items():
    print(f"::notice::{name}={short_hash(value)}")
PY
}

log_foundation_plan_summary() {
  terraform -chdir="terraform/foundation" show -json tfplan \
    | python3 -c '
import json, sys

plan = json.load(sys.stdin)
changes = []
for item in plan.get("resource_changes", []):
    addr = item.get("address", "")
    if addr.startswith("docker_config.xray_config"):
        actions = ",".join(item.get("change", {}).get("actions", []))
        after = item.get("change", {}).get("after", {}) or {}
        before = item.get("change", {}).get("before", {}) or {}
        changes.append((addr, actions, before.get("name", ""), after.get("name", "")))

if not changes:
    print("::notice::foundation.plan.xray_configs=no resource_changes")
else:
    for addr, actions, before_name, after_name in changes:
        print(f"::notice::foundation.plan.{addr}.actions={actions}")
        print(f"::notice::foundation.plan.{addr}.before_name={before_name}")
        print(f"::notice::foundation.plan.{addr}.after_name={after_name}")
'
}

verify_foundation_config_presence() {
  local config_name="$1"
  local label="$2"
  [ -n "${config_name}" ] || return 0
  command -v docker >/dev/null 2>&1 || return 0

  if docker config inspect "${config_name}" --format '{{.Spec.Name}} {{.CreatedAt}} {{.ID}}' >/tmp/foundation_config_inspect.out 2>/tmp/foundation_config_inspect.err; then
    printf '::notice::foundation.%s.inspect=%s\n' "${label}" "$(cat /tmp/foundation_config_inspect.out)"
  else
    echo "::error::Expected docker config '${config_name}' for ${label} is missing after terraform apply"
    cat /tmp/foundation_config_inspect.err >&2 || true
    exit 1
  fi
}

foundation_reconcile_state_from_plan() {
  local json_file
  json_file="$(mktemp)"
  terraform -chdir="terraform/foundation" show -json tfplan > "${json_file}"

  python3 - "${json_file}" <<'PY' | while IFS='|' read -r addr kind actions name; do
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    plan = json.load(fh)

for item in plan.get("resource_changes", []):
    addr = item.get("address", "")
    actions = ",".join(item.get("change", {}).get("actions", []))
    after = item.get("change", {}).get("after", {}) or {}
    rtype = item.get("type", "")
    name = after.get("name", "")
    print(f"{addr}|{rtype}|{actions}|{name}")
PY
    [ -n "${addr}" ] || continue
    case "${kind}" in
      docker_network)
        if [ "${actions}" = "create" ] && [ -n "${name}" ] && ! tf_state_has foundation "${addr}"; then
          local id=""
          id="$(docker network inspect -f '{{ .Id }}' "${name}" 2>/dev/null || true)"
          if [ -n "${id}" ]; then
            echo "::notice::foundation.import.network ${addr} <- ${name}"
            terraform -chdir="terraform/foundation" import "${addr}" "${id}" >/dev/null
          fi
        fi
        ;;
      docker_volume)
        if [ "${actions}" = "create" ] && [ -n "${name}" ] && ! tf_state_has foundation "${addr}"; then
          local id=""
          id="$(docker volume inspect -f '{{ .Name }}' "${name}" 2>/dev/null || true)"
          if [ -n "${id}" ]; then
            echo "::notice::foundation.import.volume ${addr} <- ${name}"
            terraform -chdir="terraform/foundation" import "${addr}" "${id}" >/dev/null
          fi
        fi
        ;;
      docker_config)
        if [ "${actions}" = "create" ] && [ -n "${name}" ] && ! tf_state_has foundation "${addr}"; then
          local id=""
          id="$(docker config inspect -f '{{ .ID }}' "${name}" 2>/dev/null || true)"
          if [ -n "${id}" ]; then
            echo "::notice::foundation.import.config ${addr} <- ${name}"
            terraform -chdir="terraform/foundation" import "${addr}" "${id}" >/dev/null
          fi
        fi

        if [ "${actions}" = "delete,create" ] && tf_state_has foundation "${addr}"; then
          echo "::notice::foundation.state_rm ${addr} to avoid destroying in-use immutable config"
          terraform -chdir="terraform/foundation" state rm "${addr}" >/dev/null
        fi
        ;;
    esac
  done

  rm -f "${json_file}"
}

prepare_nodes_replace_args() {
  local raw names_csv
  raw="${REPLACE_VPN_NODES:-}"
  names_csv="$(printf '%s' "${raw}" | tr -d '[:space:]')"
  [ -n "${names_csv}" ] || return 0

  echo "::error::REPLACE_VPN_NODES is disabled. Use lifecycle: drain -> migrate -> deactivate, then apply terraform/nodes without force-recreate."
  exit 1
}

plan_apply_root() {
  local root="$1"
  local tfvars_file="$2"
  local backend_file
  local -a plan_args=()

  backend_file="$(mktemp)"
  write_backend_config "${root}.tfstate" "${backend_file}"

  unset TF_VAR_inventory_output_path
  case "${root}" in
    nodes)       export TF_VAR_inventory_output_path="${INVENTORY_OUTPUT_PATH:-}" ;;
    infra-nodes) export TF_VAR_inventory_output_path="${INFRA_NODES_OUTPUT_PATH:-}" ;;
  esac

  terraform -chdir="terraform/${root}" init -input=false -backend-config="${backend_file}"

  if [ "${root}" = "foundation" ]; then
    log_foundation_input_fingerprints
    if terraform -chdir="terraform/${root}" state list 2>/dev/null | grep -qx 'docker_config.vault_config'; then
      terraform -chdir="terraform/${root}" state rm docker_config.vault_config
    fi
  fi

  plan_args=(-input=false -out=tfplan)
  if [ -n "${tfvars_file}" ]; then
    plan_args+=("-var-file=${tfvars_file}")
  fi

  if [ "${root}" = "nodes" ] && [ "${#NODES_REPLACE_ARGS[@]}" -gt 0 ]; then
    plan_args+=("${NODES_REPLACE_ARGS[@]}")
  fi

  terraform -chdir="terraform/${root}" plan "${plan_args[@]}"
  if [ "${root}" = "foundation" ]; then
    log_foundation_plan_summary
    foundation_reconcile_state_from_plan
    terraform -chdir="terraform/${root}" plan "${plan_args[@]}"
    log_foundation_plan_summary
  fi
  terraform -chdir="terraform/${root}" apply -input=false -auto-approve tfplan

  if [ "${root}" = "foundation" ]; then
    export_config_names
    verify_foundation_config_presence "${XRAY_CONFIG_NAME:-}" "xray"
    verify_foundation_config_presence "${XRAY_CONFIG_DEV_NAME:-}" "xray_dev"
  fi

  rm -f "${backend_file}" "terraform/${root}/tfplan"
}

init_foundation_and_export_outputs() {
  local backend_file
  backend_file="$(mktemp)"
  write_backend_config "foundation.tfstate" "${backend_file}"
  terraform -chdir="terraform/foundation" init -input=false -backend-config="${backend_file}"
  export_config_names
  rm -f "${backend_file}"
}

# ----- main --------------------------------------------------------------
main() {
  # Convert IAC_TFVAR_* → TF_VAR_*
  local script_dir
  script_dir="$(cd "$(dirname "$0")/.." && pwd)"
  # shellcheck source=scripts/core/prepare-terraform-env.sh
  source "${script_dir}/core/prepare-terraform-env.sh"

  setup_provider_mirror
  prepare_nodes_replace_args

  validate_tfvars_file "${FOUNDATION_TFVARS_FILE}" "foundation"
  validate_tfvars_file "${NODES_TFVARS_FILE}" "nodes"
  validate_tfvars_file "${INFRA_NODES_TFVARS_FILE}" "infra-nodes"

  local apply_foundation
  apply_foundation="${APPLY_FOUNDATION:-true}"

  local apply_nodes
  apply_nodes="${APPLY_NODES:-true}"

  local roots=()
  if [ "${apply_foundation}" = "true" ]; then
    roots+=(foundation)
  else
    echo "::notice::Skipping terraform/foundation apply because APPLY_FOUNDATION=false"
    echo "::group::terraform/foundation (init+outputs only)"
    init_foundation_and_export_outputs
    echo "::endgroup::"
  fi

  if [ "${apply_nodes}" = "true" ]; then
    roots+=(nodes)
  else
    echo "::notice::Skipping terraform/nodes apply because APPLY_NODES=false"
  fi

  [ "${APPLY_INFRA_NODES:-false}" != "true" ] || roots+=(infra-nodes)

  if [ "${#roots[@]}" -eq 0 ]; then
    echo "::notice::No terraform roots selected for apply"
    return 0
  fi

  for root in "${roots[@]}"; do
    echo "::group::terraform/${root}"
    case "${root}" in
      foundation)  plan_apply_root "${root}" "${FOUNDATION_TFVARS_FILE}" ;;
      nodes)       plan_apply_root "${root}" "${NODES_TFVARS_FILE}" ;;
      infra-nodes) plan_apply_root "${root}" "${INFRA_NODES_TFVARS_FILE}" ;;
    esac
    echo "::endgroup::"
  done

  [ -z "${_TF_MIRROR_CFG_TMP}" ] || rm -f "${_TF_MIRROR_CFG_TMP}"
}

main "$@"
