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
  image_id          = trimspace(each.value.image_id) != "" ? each.value.image_id : null
  image_name        = trimspace(each.value.image_name) != "" ? each.value.image_name : null
  flavor_id         = trimspace(each.value.flavor_id) != "" ? each.value.flavor_id : null
  flavor_name       = trimspace(each.value.flavor_name) != "" ? each.value.flavor_name : null
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
      server_id       = instance.id
      channel         = try(var.nodes[name].channel, "prod")
      traffic_role    = try(var.nodes[name].traffic_role, "standard")
      ssh_user        = try(var.nodes[name].ssh_user, "root")
      ssh_port        = try(var.nodes[name].ssh_port, 22)
      ssh_key_ref     = try(var.nodes[name].ssh_key_ref, "default")
      enabled         = try(var.nodes[name].enabled, true)
      region          = try(var.nodes[name].region, "")
      platform_region = try(var.nodes[name].platform_region, "")
    }
  }
}
