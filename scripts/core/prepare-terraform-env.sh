#!/usr/bin/env bash
set -Eeuo pipefail

# Prepare Terraform variables from environment in a provider-agnostic way.
#
# Supported patterns:
# 1) Native Terraform variables:
#    TF_VAR_<terraform_variable_name>
# 2) Generic alias variables:
#    IAC_TFVAR_<UPPER_SNAKE_NAME> -> TF_VAR_<lower_snake_name>
#
# This keeps CI/workflows stable when providers or variable sets change.

while IFS='=' read -r key value; do
  [[ "${key}" == IAC_TFVAR_* ]] || continue

  suffix="${key#IAC_TFVAR_}"
  if [[ -z "${suffix}" ]]; then
    continue
  fi

  tf_name="$(printf '%s' "${suffix}" | tr '[:upper:]' '[:lower:]')"
  if [[ ! "${tf_name}" =~ ^[a-z0-9_]+$ ]]; then
    echo "Skipping invalid IAC_TFVAR key: ${key}" >&2
    continue
  fi

  export "TF_VAR_${tf_name}=${value}"
done < <(env)
