terraform {
  required_version = ">= 1.8.0, < 2.0.0"

  backend "s3" {}

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.191"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

provider "yandex" {
  token                    = trimspace(var.yandex_token) != "" ? var.yandex_token : null
  service_account_key_file = trimspace(var.yandex_service_account_key_file) != "" ? var.yandex_service_account_key_file : null
  cloud_id                 = trimspace(var.yandex_cloud_id) != "" ? var.yandex_cloud_id : null
  folder_id                = trimspace(var.yandex_folder_id) != "" ? var.yandex_folder_id : null
  zone                     = trimspace(var.yandex_zone) != "" ? var.yandex_zone : null
}

# Vault provider — reads VAULT_ADDR and VAULT_TOKEN from the environment.
# Used to fetch the k3s cluster join token written to secret/data/k3s/join-token
# so new Yandex Cloud VPN nodes can install k3s-agent fully from terraform.
provider "vault" {
  skip_child_token = true
}
