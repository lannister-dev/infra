#!/usr/bin/env bash
# ---------------------------------------------------------------------
# Terraform init → plan → apply for every IaC root.
#
# Expected environment (sourced by caller from INFRA_ENV_PROD):
#   TF_STATE_BUCKET, TF_STATE_REGION, TF_STATE_KEY_PREFIX  (required)
#   TF_STATE_ENDPOINT, TF_STATE_ACCESS_KEY, …              (optional)
#   TF_PROVIDER_MIRROR_URL | TF_CLI_CONFIG_CONTENT[_B64]   (optional)
#   APPLY_INFRA_NODES=true|false                            (optional)
#   APPLY_YANDEX_VPN=true|false                             (optional)
#   INFRA_NODES_TFVARS_FILE / YANDEX_VPN_TFVARS_FILE        (optional)
# ---------------------------------------------------------------------
set -Eeo pipefail
set -u

: "${TF_STATE_BUCKET:?TF_STATE_BUCKET is required}"
: "${TF_STATE_REGION:?TF_STATE_REGION is required}"
: "${TF_STATE_KEY_PREFIX:?TF_STATE_KEY_PREFIX is required}"

# Normalize provider-agnostic aliases like IAC_TFVAR_FOO into TF_VAR_foo
# before any logging, planning, or apply steps read Terraform inputs.
source "$(dirname "${BASH_SOURCE[0]}")/../core/prepare-terraform-env.sh"

GITHUB_ENV="${GITHUB_ENV:-/dev/null}"

INFRA_NODES_TFVARS_FILE="${INFRA_NODES_TFVARS_FILE:-}"
YANDEX_VPN_TFVARS_FILE="${YANDEX_VPN_TFVARS_FILE:-}"
_YC_SA_KEY_TMP=""

# ----- provider mirror --------------------------------------------------
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

# ----- Yandex Cloud auth materialization --------------------------------
prepare_yandex_auth() {
  local key_file=""

  if [ -n "${YC_SERVICE_ACCOUNT_KEY_FILE:-}" ]; then
    key_file="${YC_SERVICE_ACCOUNT_KEY_FILE}"
    if [ ! -f "${key_file}" ]; then
      echo "::error::YC_SERVICE_ACCOUNT_KEY_FILE points to a missing file: ${key_file}"
      exit 1
    fi
  elif [ -n "${TF_VAR_yandex_service_account_key_file:-}" ]; then
    key_file="${TF_VAR_yandex_service_account_key_file}"
    if [ ! -f "${key_file}" ]; then
      echo "::error::TF_VAR_yandex_service_account_key_file points to a missing file: ${key_file}"
      exit 1
    fi
  elif [ -n "${YC_SERVICE_ACCOUNT_KEY_B64:-}" ]; then
    _YC_SA_KEY_TMP="$(mktemp)"
    printf '%s' "${YC_SERVICE_ACCOUNT_KEY_B64}" | base64 -d > "${_YC_SA_KEY_TMP}" || {
      echo "::error::Failed to decode YC_SERVICE_ACCOUNT_KEY_B64"
      exit 1
    }
    chmod 600 "${_YC_SA_KEY_TMP}"
    key_file="${_YC_SA_KEY_TMP}"
  elif [ -n "${YC_SERVICE_ACCOUNT_KEY_JSON:-}" ]; then
    _YC_SA_KEY_TMP="$(mktemp)"
    printf '%s' "${YC_SERVICE_ACCOUNT_KEY_JSON}" > "${_YC_SA_KEY_TMP}"
    chmod 600 "${_YC_SA_KEY_TMP}"
    key_file="${_YC_SA_KEY_TMP}"
  fi

  if [ -n "${key_file}" ]; then
    export YC_SERVICE_ACCOUNT_KEY_FILE="${key_file}"
    export TF_VAR_yandex_service_account_key_file="${key_file}"

    # Prefer service account auth over stale short-lived IAM tokens.
    unset YC_TOKEN || true
    unset TF_VAR_yandex_token || true
    echo "::notice::Yandex auth: using service account key file"
    return 0
  fi

  if [ -n "${YC_TOKEN:-}" ] || [ -n "${TF_VAR_yandex_token:-}" ]; then
    echo "::notice::Yandex auth: using IAM token"
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
      echo "use_path_style            = ${TF_STATE_USE_PATH_STYLE:-${TF_STATE_FORCE_PATH_STYLE:-true}}"
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

# ----- plan + apply a single root ---------------------------------------
plan_apply_root() {
  local root="$1"
  local tfvars_file="$2"
  local backend_file
  local -a plan_args=()

  backend_file="$(mktemp)"
  write_backend_config "${root}.tfstate" "${backend_file}"

  unset TF_VAR_inventory_output_path
  case "${root}" in
    infra-nodes) export TF_VAR_inventory_output_path="${INFRA_NODES_OUTPUT_PATH:-}" ;;
  esac

  terraform -chdir="terraform/${root}" init -input=false -backend-config="${backend_file}"

  plan_args=(-input=false -out=tfplan)
  if [ -n "${tfvars_file}" ]; then
    plan_args+=("-var-file=${tfvars_file}")
  fi

  terraform -chdir="terraform/${root}" plan "${plan_args[@]}"
  terraform -chdir="terraform/${root}" apply -input=false -auto-approve tfplan

  rm -f "${backend_file}" "terraform/${root}/tfplan"
}

# ----- main --------------------------------------------------------------
main() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")/.." && pwd)"
  # shellcheck source=scripts/core/prepare-terraform-env.sh
  source "${script_dir}/core/prepare-terraform-env.sh"

  setup_provider_mirror
  prepare_yandex_auth

  validate_tfvars_file "${INFRA_NODES_TFVARS_FILE}" "infra-nodes"
  validate_tfvars_file "${YANDEX_VPN_TFVARS_FILE}" "yandex-vpn"

  local roots=()
  [ "${APPLY_INFRA_NODES:-false}" != "true" ] || roots+=(infra-nodes)
  [ "${APPLY_YANDEX_VPN:-false}" != "true" ]  || roots+=(yandex-vpn)

  if [ "${#roots[@]}" -eq 0 ]; then
    echo "::notice::No terraform roots selected for apply"
    return 0
  fi

  for root in "${roots[@]}"; do
    echo "::group::terraform/${root}"
    case "${root}" in
      infra-nodes) plan_apply_root "${root}" "${INFRA_NODES_TFVARS_FILE}" ;;
      yandex-vpn)  plan_apply_root "${root}" "${YANDEX_VPN_TFVARS_FILE}" ;;
    esac
    echo "::endgroup::"
  done

  [ -z "${_TF_MIRROR_CFG_TMP}" ] || rm -f "${_TF_MIRROR_CFG_TMP}"
  [ -z "${_YC_SA_KEY_TMP}" ] || rm -f "${_YC_SA_KEY_TMP}"
}

main "$@"
