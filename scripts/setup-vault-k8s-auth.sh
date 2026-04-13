#!/usr/bin/env bash
# Setup Vault Kubernetes auth for External Secrets Operator
#
# Run once after ESO is installed:
#   bash scripts/setup-vault-k8s-auth.sh
#
# Prerequisites:
#   - kubectl access to K3s cluster
#   - VAULT_ADDR and VAULT_TOKEN environment variables set
#
set -Eeuo pipefail

: "${VAULT_ADDR:?Set VAULT_ADDR (e.g. https://vault.lannister-dev.ru)}"
: "${VAULT_TOKEN:?Set VAULT_TOKEN (root or admin token)}"

echo "==> Enabling Kubernetes auth method..."
vault auth enable kubernetes 2>/dev/null || echo "    (already enabled)"

echo "==> Configuring Kubernetes auth..."
# K3s API server CA and JWT from inside the cluster
K8S_HOST="https://kubernetes.default.svc.cluster.local:443"
K8S_CA_CERT=$(kubectl exec -n vault vault-0 -- cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)
TOKEN_REVIEWER_JWT=$(kubectl exec -n vault vault-0 -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)

vault write auth/kubernetes/config \
  kubernetes_host="$K8S_HOST" \
  kubernetes_ca_cert="$K8S_CA_CERT" \
  token_reviewer_jwt="$TOKEN_REVIEWER_JWT"

echo "==> Creating policy for ESO..."
vault policy write external-secrets - <<'POLICY'
# Read-only access to control-plane secrets for ESO
path "kv/data/control-plane/*" {
  capabilities = ["read"]
}
path "kv/metadata/control-plane/*" {
  capabilities = ["read", "list"]
}
POLICY

echo "==> Creating Kubernetes auth role for ESO..."
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names="external-secrets" \
  bound_service_account_namespaces="external-secrets" \
  policies="external-secrets" \
  ttl="1h"

echo "==> Done. ESO can now authenticate to Vault."
echo ""
echo "Next step: migrate env blob to individual KV fields:"
echo "  bash scripts/vault-migrate-env-secrets.sh"
