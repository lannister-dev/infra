#!/usr/bin/env bash
# Migrate control-api .env blob from Vault KV to individual fields
#
# Currently: kv/control-plane/{prod,dev} has a single "config" field
#            containing the entire .env file as a blob
#
# After:     kv/control-plane/{prod,dev}/env has each variable as a
#            separate field — compatible with External Secrets Operator
#
# Usage:
#   export VAULT_ADDR=https://vault.lannister-dev.ru
#   export VAULT_TOKEN=<token>
#   bash scripts/vault-migrate-env-secrets.sh prod
#   bash scripts/vault-migrate-env-secrets.sh dev
#
set -Eeuo pipefail

: "${VAULT_ADDR:?Set VAULT_ADDR}"
: "${VAULT_TOKEN:?Set VAULT_TOKEN}"

SCOPE="${1:?Usage: $0 <prod|dev>}"

echo "==> Reading config blob from kv/control-plane/${SCOPE}..."
BLOB=$(vault kv get -mount=kv -field=config "control-plane/${SCOPE}")

if [ -z "$BLOB" ]; then
  echo "ERROR: config field is empty at kv/control-plane/${SCOPE}"
  exit 1
fi

# Parse .env lines into vault kv put arguments
# Skips comments and empty lines
ARGS=()
while IFS= read -r line; do
  # Skip empty lines and comments
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  # Extract KEY=VALUE
  key="${line%%=*}"
  value="${line#*=}"
  # Strip surrounding quotes if present
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  ARGS+=("${key}=${value}")
done <<< "$BLOB"

echo "==> Found ${#ARGS[@]} variables"
echo "==> Writing to kv/control-plane/${SCOPE}/env..."

vault kv put -mount=kv "control-plane/${SCOPE}/env" "${ARGS[@]}"

echo "==> Done. Verify with:"
echo "    vault kv get -mount=kv control-plane/${SCOPE}/env"
echo ""
echo "The original blob at kv/control-plane/${SCOPE} is untouched."
echo "CI will continue to work until you remove the secret creation step."
