output "vpn_nodes" {
  description = "Normalized desired VPN nodes."
  value       = local.vpn_nodes_list
}

output "enabled_vpn_nodes" {
  description = "Enabled VPN nodes that should be reconciled."
  value       = local.enabled_vpn_nodes_list
}

output "provider_api_vpn_nodes" {
  description = "VPN nodes resolved from HostVDS OpenStack API."
  value       = local.provider_api_vpn_nodes
}

output "hostvds_compute_vpn_nodes" {
  description = "VPN nodes provisioned in HostVDS compute module."
  value       = local.hostvds_compute_vpn_nodes
}

output "inventory_output_path" {
  description = "Generated Ansible inventory variables file path."
  value       = local_file.vpn_nodes_inventory.filename
}
