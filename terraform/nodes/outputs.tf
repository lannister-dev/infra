output "vpn_nodes" {
  description = "Normalized desired VPN nodes."
  value       = local.vpn_nodes_list
}

output "enabled_vpn_nodes" {
  description = "Enabled VPN nodes that should be reconciled."
  value       = local.enabled_vpn_nodes_list
}

output "provider_api_vpn_nodes" {
  description = "VPN nodes resolved from provider API modules (currently HostVDS)."
  value       = local.provider_api_vpn_nodes
}

output "hostvds_compute_vpn_nodes" {
  description = "VPN nodes provisioned in HostVDS compute module."
  value       = local.hostvds_compute_vpn_nodes
}

output "yandex_whitelist_entry_vpn_nodes" {
  description = "Yandex Cloud whitelist entry VPN nodes adopted into Terraform."
  value       = local.yandex_whitelist_entry_vpn_nodes
}

output "provider_api_catalog_hostvds_input" {
  description = "Effective HostVDS API catalog input after merging provider_api_vpn_nodes + legacy maps + compute outputs."
  value       = local.hostvds_api_input_nodes
}

output "provider_compute_catalog_hostvds_input" {
  description = "Effective HostVDS compute catalog input after merging provider_compute_vpn_nodes + legacy maps."
  value       = local.hostvds_compute_input_nodes
}

output "yandex_whitelist_entry_catalog" {
  description = "Effective Yandex Cloud whitelist entry catalog."
  value       = var.yandex_whitelist_entry_nodes
}

output "inventory_output_path" {
  description = "Generated Ansible inventory variables file path."
  value       = local_file.vpn_nodes_inventory.filename
}
