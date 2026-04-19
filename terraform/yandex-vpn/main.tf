module "yandex_vpn_entry" {
  source = "./modules/yandex-vpn-entry"
  count  = length(var.yandex_vpn_nodes) > 0 ? 1 : 0

  providers = {
    yandex = yandex
  }

  nodes             = var.yandex_vpn_nodes
  ssh_identity_file = var.ssh_identity_file
}
