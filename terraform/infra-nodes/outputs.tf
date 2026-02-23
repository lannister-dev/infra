output "infra_nodes" {
  description = "Normalized infra nodes catalog."
  value       = local.infra_nodes_list
}

output "provider_api_infra_nodes" {
  description = "Infra nodes resolved from Timeweb API."
  value       = local.provider_api_infra_nodes
}

output "timeweb_compute_infra_nodes" {
  description = "Infra nodes provisioned via Timeweb compute module."
  value       = local.timeweb_compute_infra_nodes
}

output "inventory_output_path" {
  description = "Generated infra inventory output path."
  value       = local_file.infra_nodes_inventory.filename
}
