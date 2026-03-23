locals {
  root_dir = "${path.module}/../.."

  default_inventory_output_path  = "${local.root_dir}/ansible/inventory/generated/vpn_nodes.yml"
  resolved_inventory_output_path = trimspace(var.inventory_output_path) != "" ? var.inventory_output_path : local.default_inventory_output_path

  hostvds_api_from_provider_catalog = {
    for name, node in var.provider_api_vpn_nodes : name => {
      server_id       = node.server_id
      channel         = node.channel
      ssh_user        = node.ssh_user
      ssh_port        = node.ssh_port
      ssh_key_ref     = node.ssh_key_ref
      enabled         = node.enabled
      region          = node.region
      platform_region = node.platform_region
    } if lower(trimspace(node.provider)) == "hostvds"
  }

  hostvds_compute_from_provider_catalog = {
    for name, node in var.provider_compute_vpn_nodes : name => {
      name              = node.name
      image_id          = node.image_id
      image_name        = node.image_name
      flavor_id         = node.flavor_id
      flavor_name       = node.flavor_name
      network_ids       = node.network_ids
      key_pair          = node.key_pair
      security_groups   = node.security_groups
      availability_zone = node.availability_zone
      user_data         = node.user_data
      metadata          = node.metadata
      channel           = node.channel
      ssh_user          = node.ssh_user
      ssh_port          = node.ssh_port
      ssh_key_ref       = node.ssh_key_ref
      enabled           = node.enabled
      region            = node.region
      platform_region   = node.platform_region
    } if lower(trimspace(node.provider)) == "hostvds"
  }

  hostvds_compute_input_nodes       = merge(var.hostvds_provisioned_vpn_nodes, local.hostvds_compute_from_provider_catalog)
  hostvds_compute_enabled_effective = var.hostvds_compute_enabled || length(local.hostvds_compute_input_nodes) > 0

  hostvds_compute_vpn_nodes        = local.hostvds_compute_enabled_effective ? module.hostvds_compute[0].vpn_nodes : {}
  yandex_whitelist_entry_vpn_nodes = length(var.yandex_whitelist_entry_nodes) > 0 ? module.yandex_whitelist_entry[0].vpn_nodes : {}
  hostvds_api_input_nodes          = merge(var.hostvds_vpn_nodes, local.hostvds_api_from_provider_catalog, local.hostvds_compute_vpn_nodes)
  hostvds_api_enabled              = var.provider_api_enabled || local.hostvds_compute_enabled_effective || length(var.hostvds_vpn_nodes) > 0 || length(local.hostvds_api_from_provider_catalog) > 0
  hostvds_credentials_required = (
    length(var.hostvds_vpn_nodes) > 0
    || length(local.hostvds_api_from_provider_catalog) > 0
    || local.hostvds_compute_enabled_effective
  )

  provider_api_vpn_nodes = module.hostvds_api_catalog.vpn_nodes

  merged_vpn_nodes_raw = merge(var.vpn_nodes, local.provider_api_vpn_nodes, local.yandex_whitelist_entry_vpn_nodes)

  merged_vpn_nodes = {
    for name, node in local.merged_vpn_nodes_raw : name => {
      public_ip       = tostring(try(node["public_ip"], ""))
      channel         = tostring(try(node["channel"], "prod"))
      ssh_user        = tostring(try(node["ssh_user"], "root"))
      ssh_port        = tonumber(try(node["ssh_port"], 22))
      ssh_key_ref     = tostring(try(node["ssh_key_ref"], "default"))
      enabled         = try(node["enabled"], true)
      provider        = tostring(try(node["provider"], "api"))
      region          = tostring(try(node["region"], ""))
      platform_region = tostring(try(node["platform_region"], ""))
      traffic_role    = tostring(try(node["traffic_role"], "standard"))
    }
  }

  vpn_nodes_list = [
    for name in sort(keys(local.merged_vpn_nodes)) : {
      name            = name
      public_ip       = local.merged_vpn_nodes[name]["public_ip"]
      channel         = local.merged_vpn_nodes[name]["channel"]
      ssh_user        = local.merged_vpn_nodes[name]["ssh_user"]
      ssh_port        = local.merged_vpn_nodes[name]["ssh_port"]
      ssh_key_ref     = local.merged_vpn_nodes[name]["ssh_key_ref"]
      enabled         = local.merged_vpn_nodes[name]["enabled"]
      provider        = local.merged_vpn_nodes[name]["provider"]
      region          = local.merged_vpn_nodes[name]["region"]
      platform_region = local.merged_vpn_nodes[name]["platform_region"]
      traffic_role    = local.merged_vpn_nodes[name]["traffic_role"]
    }
  ]

  enabled_vpn_nodes_list = [
    for node in local.vpn_nodes_list : node if node.enabled
  ]
}
