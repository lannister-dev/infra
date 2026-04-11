# K8s / K3s management
# Usage:
#   make ns              — apply namespaces
#   make install-data    — deploy data chart to dev/prod
#   make install-nats    — deploy NATS
#   make install-xray    — deploy xray
#   make status          — cluster overview
#   make lint            — helm lint all charts

SHELL := /bin/bash
.DEFAULT_GOAL := help

CHARTS_DIR := charts
VALUES_DIR := values
NS_FILE := namespaces/namespaces.yml

# ── Namespaces ──────────────────────────────────────────────
.PHONY: ns
ns: ## Apply namespaces
	kubectl apply -f $(NS_FILE)

# ── Data service aliases ──────────────────────────────────
.PHONY: install-data-service-aliases
install-data-service-aliases: ## Create app-facing postgres/redis aliases in K8s app namespaces
	kubectl apply -f manifests/data-service-aliases.yaml

# ── Data (PostgreSQL + Redis) ──────────────────────────────
.PHONY: install-data-dev
install-data-dev: ## Deploy data chart to data-dev namespace
	helm upgrade --install data-dev $(CHARTS_DIR)/data \
		-n data-dev --create-namespace \
		-f $(VALUES_DIR)/dev/data.yaml

.PHONY: install-data-prod
install-data-prod: ## Deploy data chart to data-prod namespace
	helm upgrade --install data-prod $(CHARTS_DIR)/data \
		-n data-prod --create-namespace \
		-f $(VALUES_DIR)/prod/data.yaml

.PHONY: install-data
install-data: install-data-dev install-data-prod ## Deploy data to both envs

# ── NATS (official chart) ─────────────────────────────────
.PHONY: install-nats
install-nats: ## Deploy NATS (official Helm chart)
	helm repo add nats https://nats-io.github.io/k8s/helm/charts/ 2>/dev/null || true
	helm repo update nats
	helm upgrade --install nats nats/nats \
		-n nats --create-namespace \
		-f $(VALUES_DIR)/prod/nats.yaml

# ── Vault (official chart) ───────────────────────────────
.PHONY: install-vault
install-vault: ## Deploy Vault (official Helm chart)
	helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
	helm repo update hashicorp
	helm upgrade --install vault hashicorp/vault \
		-n vault --create-namespace \
		-f $(VALUES_DIR)/prod/vault.yaml

# ── Monitoring (kube-prometheus-stack) ────────────────────
.PHONY: install-monitoring
install-monitoring: ## Deploy kube-prometheus-stack
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
	helm repo update prometheus-community
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
		-n monitoring --create-namespace \
		-f $(VALUES_DIR)/prod/monitoring.yaml

.PHONY: uninstall-monitoring
uninstall-monitoring: ## Remove monitoring stack
	helm uninstall monitoring -n monitoring 2>/dev/null || true

# ── VPN Xray ──────────────────────────────────────────────
.PHONY: install-xray
install-xray: ## Deploy xray to vpn-prod
	helm upgrade --install vpn-xray $(CHARTS_DIR)/vpn-xray \
		-n vpn-prod --create-namespace \
		-f $(VALUES_DIR)/prod/vpn-xray.yaml

.PHONY: install-xray-dev
install-xray-dev: ## Deploy xray to vpn-dev
	helm upgrade --install vpn-xray-dev $(CHARTS_DIR)/vpn-xray \
		-n vpn-dev --create-namespace \
		-f $(VALUES_DIR)/dev/vpn-xray.yaml

# ── All ───────────────────────────────────────────────────
.PHONY: install-all
install-all: ns install-monitoring install-data install-data-service-aliases install-nats install-vault install-xray ## Deploy everything

# ── Status ────────────────────────────────────────────────
.PHONY: status
status: ## Cluster overview
	@echo "=== Nodes ==="
	@kubectl get nodes -o wide
	@echo ""
	@echo "=== Pods (all namespaces) ==="
	@kubectl get pods -A -o wide
	@echo ""
	@echo "=== Services ==="
	@kubectl get svc -A

# ── Lint ──────────────────────────────────────────────────
.PHONY: lint
lint: ## Helm lint all charts
	@for chart in $(CHARTS_DIR)/*/; do \
		echo "Linting $$chart..."; \
		helm lint "$$chart" || exit 1; \
	done

# ── Uninstall ─────────────────────────────────────────────
.PHONY: uninstall-data-dev
uninstall-data-dev: ## Remove data-dev
	helm uninstall data-dev -n data-dev 2>/dev/null || true

.PHONY: uninstall-data-prod
uninstall-data-prod: ## Remove data-prod
	helm uninstall data-prod -n data-prod 2>/dev/null || true

.PHONY: uninstall-nats
uninstall-nats: ## Remove NATS
	helm uninstall nats -n nats 2>/dev/null || true

.PHONY: uninstall-vault
uninstall-vault: ## Remove Vault
	helm uninstall vault -n vault 2>/dev/null || true

.PHONY: uninstall-xray
uninstall-xray: ## Remove xray
	helm uninstall vpn-xray -n vpn-prod 2>/dev/null || true

# ── Help ──────────────────────────────────────────────────
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
