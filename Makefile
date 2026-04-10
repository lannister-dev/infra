# Infrastructure Makefile
# Usage: make <target> [ENV=dev|prod] [TF_ARGS=...] [ANSIBLE_ARGS=...]

SHELL := /bin/bash
.DEFAULT_GOAL := help

ENV          ?= prod
TF_ARGS      ?=
ANSIBLE_ARGS ?=

REPO_ROOT    := $(CURDIR)
TF_ROOTS     := foundation nodes infra-nodes
INVENTORY    := ansible/inventory/production.ini
ANSIBLE_CFG  := ansible/ansible.cfg

# Load .env if present (ignore errors when missing)
-include .env
export

define load_env
	@set -a && [ -f .env ] && source .env; set +a
endef

# ---------- Terraform ----------

.PHONY: init
init: ## terraform init for all roots
	@for root in $(TF_ROOTS); do \
		echo "==> terraform init: $${root}"; \
		terraform -chdir=terraform/$${root} init -input=false \
			-backend-config="$(REPO_ROOT)/terraform/backends/$${root}.hcl" \
			$(TF_ARGS) || exit 1; \
	done

.PHONY: plan
plan: ## terraform plan for all roots
	@for root in $(TF_ROOTS); do \
		echo "==> terraform plan: $${root}"; \
		terraform -chdir=terraform/$${root} plan -input=false $(TF_ARGS) || exit 1; \
	done

.PHONY: apply
apply: ## terraform apply for all roots (sequential)
	@for root in $(TF_ROOTS); do \
		echo "==> terraform apply: $${root}"; \
		terraform -chdir=terraform/$${root} apply -input=false -auto-approve $(TF_ARGS) || exit 1; \
	done

.PHONY: fmt
fmt: ## terraform fmt for all roots
	@for root in $(TF_ROOTS); do \
		terraform fmt terraform/$${root}; \
	done

# ---------- Ansible ----------

.PHONY: deploy
deploy: apply ## Full cycle: apply + ansible reconcile + deploy-stacks
	REPO_ROOT=$(REPO_ROOT) ANSIBLE_CONFIG=$(REPO_ROOT)/$(ANSIBLE_CFG) \
		ansible-playbook -i $(INVENTORY) ansible/playbooks/reconcile-infra-nodes.yml $(ANSIBLE_ARGS)
	REPO_ROOT=$(REPO_ROOT) ANSIBLE_CONFIG=$(REPO_ROOT)/$(ANSIBLE_CFG) \
		ansible-playbook -i $(INVENTORY) ansible/playbooks/reconcile-vpn-nodes.yml $(ANSIBLE_ARGS)
	REPO_ROOT=$(REPO_ROOT) ANSIBLE_CONFIG=$(REPO_ROOT)/$(ANSIBLE_CFG) \
		ansible-playbook -i $(INVENTORY) ansible/playbooks/deploy-stacks.yml $(ANSIBLE_ARGS)

.PHONY: deploy-vpn
deploy-vpn: ## Reconcile VPN nodes only
	REPO_ROOT=$(REPO_ROOT) ANSIBLE_CONFIG=$(REPO_ROOT)/$(ANSIBLE_CFG) \
		ansible-playbook -i $(INVENTORY) ansible/playbooks/reconcile-vpn-nodes.yml $(ANSIBLE_ARGS)

.PHONY: deploy-data
deploy-data: ## Deploy data stacks only
	REPO_ROOT=$(REPO_ROOT) ANSIBLE_CONFIG=$(REPO_ROOT)/$(ANSIBLE_CFG) \
		ansible-playbook -i $(INVENTORY) ansible/playbooks/deploy-data-stacks.yml $(ANSIBLE_ARGS)

.PHONY: deploy-stacks
deploy-stacks: ## Deploy all swarm stacks
	REPO_ROOT=$(REPO_ROOT) ANSIBLE_CONFIG=$(REPO_ROOT)/$(ANSIBLE_CFG) \
		ansible-playbook -i $(INVENTORY) ansible/playbooks/deploy-stacks.yml $(ANSIBLE_ARGS)

# ---------- Quality ----------

.PHONY: lint
lint: ## Run all linters (terraform fmt check, tflint, ansible-lint, shellcheck, ruff, mypy)
	@echo "==> terraform fmt -check"
	@fail=0; for root in $(TF_ROOTS); do \
		terraform fmt -check -diff terraform/$${root} || fail=1; \
	done; [ $$fail -eq 0 ]
	@echo "==> tflint"
	@if command -v tflint >/dev/null 2>&1; then \
		for root in $(TF_ROOTS); do (cd terraform/$${root} && tflint) || exit 1; done; \
	else echo "  tflint not installed, skipping"; fi
	@echo "==> ansible-lint"
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint ansible/; \
	else echo "  ansible-lint not installed, skipping"; fi
	@echo "==> shellcheck"
	@if command -v shellcheck >/dev/null 2>&1; then \
		find scripts/ -name '*.sh' -exec shellcheck {} +; \
	else echo "  shellcheck not installed, skipping"; fi
	@echo "==> ruff"
	@if command -v ruff >/dev/null 2>&1; then \
		ruff check .; \
	else echo "  ruff not installed, skipping"; fi
	@echo "==> mypy"
	@if command -v mypy >/dev/null 2>&1; then \
		mypy scripts/ tests/ --ignore-missing-imports; \
	else echo "  mypy not installed, skipping"; fi

.PHONY: test
test: ## Run pytest
	pytest

# ---------- Help ----------

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
