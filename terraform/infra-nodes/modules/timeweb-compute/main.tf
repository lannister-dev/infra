terraform {
  required_providers {
    twc = {
      source = "tf.timeweb.cloud/timeweb-cloud/timeweb-cloud"
    }
  }
}

resource "twc_server" "infra" {
  for_each = var.nodes

  name              = trimspace(each.value.name) != "" ? each.value.name : each.key
  os_id             = each.value.os_id
  preset_id         = each.value.preset_id
  availability_zone = trimspace(each.value.availability_zone) != "" ? each.value.availability_zone : (
    trimspace(each.value.location) != "" ? each.value.location : null
  )
  project_id   = try(each.value.project_id, null)
  software_id  = try(each.value.software_id, null)
  ssh_keys_ids = each.value.ssh_keys_ids
  cloud_init   = trimspace(each.value.cloud_init) != "" ? each.value.cloud_init : null
}

locals {
  infra_nodes = {
    for name, server in twc_server.infra : name => {
      public_ip = server.main_ipv4
      role      = try(var.nodes[name].role, "worker")
      kind      = try(var.nodes[name].kind, "prod")
      ssh_user  = try(var.nodes[name].ssh_user, "root")
      ssh_port  = try(var.nodes[name].ssh_port, 22)
      enabled   = try(var.nodes[name].enabled, true)
      provider  = "timeweb-compute"
      region    = trimspace(try(var.nodes[name].region, "")) != "" ? try(var.nodes[name].region, "") : trimspace(try(var.nodes[name].location, ""))
    }
  }
}
