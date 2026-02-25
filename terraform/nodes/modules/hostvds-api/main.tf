locals {
  node_server_ids = {
    for name, node in var.nodes : name => node.server_id
  }
}

data "external" "node_lookup" {
  for_each = var.enabled ? local.node_server_ids : {}
  program  = ["python3", "${path.module}/scripts/resolve_node.py"]

  query = {
    provider               = "hostvds-openstack"
    os_auth_url            = var.os_auth_url
    os_username            = var.os_username
    os_password            = var.os_password
    os_project_name        = var.os_project_name
    os_user_domain_name    = var.os_user_domain_name
    os_user_domain_id      = var.os_user_domain_id
    os_project_domain_name = var.os_project_domain_name
    os_project_domain_id   = var.os_project_domain_id
    os_region_name         = trimspace(var.nodes[each.key].region) != "" ? var.nodes[each.key].region : var.os_region_name
    os_interface           = var.os_interface
    server_id              = each.value
  }
}

locals {
  vpn_nodes = {
    for name, node in var.nodes : name => {
      public_ip = data.external.node_lookup[name].result.public_ip
      channel   = try(node.channel, "prod")
      ssh_user  = try(node.ssh_user, "root")
      ssh_port  = try(node.ssh_port, 22)
      enabled   = try(node.enabled, true)
      provider  = "hostvds-api"
      region    = trimspace(try(node.region, "")) != "" ? try(node.region, "") : try(data.external.node_lookup[name].result.region, "")
    }
    if var.enabled
  }
}
