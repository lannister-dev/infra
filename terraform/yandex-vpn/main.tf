locals {
  needs_k3s_join_token = anytrue([
    for name, node in var.yandex_vpn_nodes : node.k3s_install != null
  ])
  k3s_vault_path = local.needs_k3s_join_token && trimspace(var.k3s_join_token_vault_path) != "" ? var.k3s_join_token_vault_path : ""
}

# Fetch the k3s cluster-join token + server URL from Vault. Only queried
# when at least one node in `yandex_vpn_nodes` has `k3s_install` set, so
# runs without Vault access are not blocked. VAULT_ADDR and VAULT_TOKEN
# come from the environment.
data "vault_kv_secret_v2" "k3s_join_token" {
  count = local.k3s_vault_path != "" ? 1 : 0
  mount = split("/", local.k3s_vault_path)[0]
  name  = join("/", slice(split("/", local.k3s_vault_path), 1, length(split("/", local.k3s_vault_path))))
}

module "yandex_vpn_entry" {
  source = "./modules/yandex-vpn-entry"
  count  = length(var.yandex_vpn_nodes) > 0 ? 1 : 0

  providers = {
    yandex = yandex
  }

  nodes             = var.yandex_vpn_nodes
  ssh_identity_file = var.ssh_identity_file
  ssh_user          = var.ssh_user
  k3s_join_url      = local.k3s_vault_path != "" ? try(data.vault_kv_secret_v2.k3s_join_token[0].data["url"], "") : ""
  k3s_join_token    = local.k3s_vault_path != "" ? try(data.vault_kv_secret_v2.k3s_join_token[0].data["token"], "") : ""
}
