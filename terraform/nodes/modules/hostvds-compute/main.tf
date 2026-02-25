terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}

resource "openstack_compute_instance_v2" "vpn" {
  for_each = var.nodes

  name              = trimspace(each.value.name) != "" ? each.value.name : each.key
  region            = trimspace(try(each.value.region, "")) != "" ? each.value.region : null
  image_id          = each.value.image_id
  flavor_id         = each.value.flavor_id
  key_pair          = trimspace(each.value.key_pair) != "" ? each.value.key_pair : null
  security_groups   = each.value.security_groups
  availability_zone = trimspace(each.value.availability_zone) != "" ? each.value.availability_zone : null
  user_data         = trimspace(each.value.user_data) != "" ? each.value.user_data : null
  metadata = merge(
    {
      managed_by = "terraform"
      role       = "vpn"
      peer_name  = each.key
    },
    each.value.metadata,
  )

  dynamic "network" {
    for_each = each.value.network_ids
    content {
      uuid = network.value
    }
  }
}

locals {
  vpn_nodes = {
    for name, instance in openstack_compute_instance_v2.vpn : name => {
      server_id = instance.id
      channel   = try(var.nodes[name].channel, "prod")
      ssh_user  = try(var.nodes[name].ssh_user, "root")
      ssh_port  = try(var.nodes[name].ssh_port, 22)
      enabled   = try(var.nodes[name].enabled, true)
      region    = try(var.nodes[name].region, "")
    }
  }
}
