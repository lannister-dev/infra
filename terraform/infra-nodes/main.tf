module "timeweb_compute" {
  source = "./modules/timeweb-compute"
  count  = var.timeweb_compute_enabled ? 1 : 0

  providers = {
    twc = twc
  }

  nodes = var.timeweb_provisioned_infra_nodes
}

module "timeweb_api_catalog" {
  source = "./modules/timeweb-api"

  enabled           = var.provider_api_enabled
  api_url           = var.timeweb_api_url
  api_token         = var.timeweb_api_token
  auth_header       = var.timeweb_auth_header
  auth_scheme       = var.timeweb_auth_scheme
  endpoint_template = var.timeweb_endpoint_template
  nodes             = var.timeweb_infra_nodes
}

locals {
  root_dir = "${path.module}/../.."

  default_inventory_output_path  = "${local.root_dir}/ansible/inventory/generated/infra_nodes.yml"
  resolved_inventory_output_path = trimspace(var.inventory_output_path) != "" ? var.inventory_output_path : local.default_inventory_output_path

  timeweb_compute_infra_nodes = var.timeweb_compute_enabled ? module.timeweb_compute[0].infra_nodes : {}
  provider_api_infra_nodes    = module.timeweb_api_catalog.infra_nodes
  merged_infra_nodes_raw      = merge(var.infra_nodes, local.provider_api_infra_nodes, local.timeweb_compute_infra_nodes)

  merged_infra_nodes = {
    for name, node in local.merged_infra_nodes_raw : name => {
      public_ip   = tostring(coalesce(try(node["public_ip"], null), ""))
      role        = tostring(try(node["role"], "worker"))
      kind        = tostring(try(node["kind"], "prod"))
      ssh_user    = tostring(try(node["ssh_user"], "root"))
      ssh_port    = tonumber(try(node["ssh_port"], 22))
      ssh_key_ref = tostring(try(node["ssh_key_ref"], "default"))
      enabled     = try(node["enabled"], true)
      provider    = tostring(try(node["provider"], "manual"))
      region      = tostring(try(node["region"], ""))
    }
  }

  infra_nodes_list = [
    for name in sort(keys(local.merged_infra_nodes)) : {
      name        = name
      public_ip   = local.merged_infra_nodes[name]["public_ip"]
      role        = local.merged_infra_nodes[name]["role"]
      kind        = local.merged_infra_nodes[name]["kind"]
      ssh_user    = local.merged_infra_nodes[name]["ssh_user"]
      ssh_port    = local.merged_infra_nodes[name]["ssh_port"]
      ssh_key_ref = local.merged_infra_nodes[name]["ssh_key_ref"]
      enabled     = local.merged_infra_nodes[name]["enabled"]
      provider    = local.merged_infra_nodes[name]["provider"]
      region      = local.merged_infra_nodes[name]["region"]
    }
  ]
}

resource "local_file" "infra_nodes_inventory" {
  filename        = local.resolved_inventory_output_path
  file_permission = "0600"
  content = yamlencode({
    infra_nodes = local.infra_nodes_list
  })

  lifecycle {
    precondition {
      condition     = !var.provider_api_enabled || length(var.timeweb_infra_nodes) == 0 || trimspace(var.timeweb_api_token) != ""
      error_message = "timeweb_api_token is required when provider_api_enabled=true and timeweb_infra_nodes is not empty."
    }

    precondition {
      condition     = !var.timeweb_compute_enabled || length(var.timeweb_provisioned_infra_nodes) == 0 || trimspace(var.timeweb_api_token) != ""
      error_message = "timeweb_api_token is required when timeweb_compute_enabled=true and timeweb_provisioned_infra_nodes is not empty."
    }

    precondition {
      condition = alltrue([
        for name, node in local.merged_infra_nodes : (
          !try(node.enabled, true) || length(trimspace(node.public_ip)) > 0
        )
      ])
      error_message = "Every enabled infra node must have a non-empty public_ip in generated inventory."
    }
  }
}
