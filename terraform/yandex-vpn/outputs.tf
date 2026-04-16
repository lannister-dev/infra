output "yandex_vpn_nodes" {
  description = "Managed Yandex Cloud VPN nodes with resolved public IP."
  value       = length(module.yandex_vpn_entry) > 0 ? module.yandex_vpn_entry[0].nodes : {}
}
