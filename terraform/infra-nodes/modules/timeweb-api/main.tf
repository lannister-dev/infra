locals {
  node_server_ids = {
    for name, node in var.nodes : name => node.server_id
  }
}

data "external" "node_lookup" {
  for_each = var.enabled ? local.node_server_ids : {}
  program  = ["python3", "${path.module}/scripts/resolve_node.py"]

  query = {
    provider          = "timeweb"
    api_url           = var.api_url
    api_token         = var.api_token
    auth_header       = var.auth_header
    auth_scheme       = var.auth_scheme
    endpoint_template = var.endpoint_template
    server_id         = each.value
  }
}

locals {
  infra_nodes = {
    for name, node in var.nodes : name => {
      public_ip = data.external.node_lookup[name].result.public_ip
      role      = try(node.role, "worker")
      kind      = try(node.kind, "prod")
      ssh_user  = try(node.ssh_user, "root")
      ssh_port  = try(node.ssh_port, 22)
      enabled   = try(node.enabled, true)
      provider  = "timeweb-api"
      region    = trimspace(try(node.region, "")) != "" ? try(node.region, "") : try(data.external.node_lookup[name].result.region, "")
    }
    if var.enabled
  }
}
