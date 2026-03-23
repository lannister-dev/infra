terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

data "yandex_compute_instance" "existing" {
  for_each    = var.nodes
  instance_id = each.value.instance_id
}

data "yandex_vpc_address" "existing" {
  for_each   = var.nodes
  address_id = each.value.address_id
}

data "yandex_vpc_security_group" "existing" {
  for_each          = var.nodes
  security_group_id = each.value.security_group_id
}

locals {
  required_ingress_rules = {
    for name, node in var.nodes : name => [
      {
        description       = "Allow SSH for whitelist entry"
        labels            = {}
        protocol          = "TCP"
        port              = 22
        from_port         = null
        to_port           = null
        v4_cidr_blocks    = sort(node.ssh_ingress_cidrs)
        v6_cidr_blocks    = []
        predefined_target = null
        security_group_id = null
      },
      {
        description       = "Allow HTTPS for whitelist entry"
        labels            = {}
        protocol          = "TCP"
        port              = 443
        from_port         = null
        to_port           = null
        v4_cidr_blocks    = sort(node.https_ingress_cidrs)
        v6_cidr_blocks    = []
        predefined_target = null
        security_group_id = null
      },
    ]
  }

  existing_ingress_rules = {
    for name, group in data.yandex_vpc_security_group.existing : name => [
      for rule in group.ingress : {
        description       = try(rule.description, null)
        labels            = try(rule.labels, {})
        protocol          = rule.protocol
        port              = try(rule.port, null)
        from_port         = try(rule.from_port, null)
        to_port           = try(rule.to_port, null)
        v4_cidr_blocks    = sort(try(rule.v4_cidr_blocks, []))
        v6_cidr_blocks    = sort(try(rule.v6_cidr_blocks, []))
        predefined_target = try(rule.predefined_target, null)
        security_group_id = try(rule.security_group_id, null)
      }
    ]
  }

  existing_egress_rules = {
    for name, group in data.yandex_vpc_security_group.existing : name => [
      for rule in group.egress : {
        description       = try(rule.description, null)
        labels            = try(rule.labels, {})
        protocol          = rule.protocol
        port              = try(rule.port, null)
        from_port         = try(rule.from_port, null)
        to_port           = try(rule.to_port, null)
        v4_cidr_blocks    = sort(try(rule.v4_cidr_blocks, []))
        v6_cidr_blocks    = sort(try(rule.v6_cidr_blocks, []))
        predefined_target = try(rule.predefined_target, null)
        security_group_id = try(rule.security_group_id, null)
      }
    ]
  }

  merged_ingress_rules = {
    for name, node in var.nodes : name => values({
      for rule in concat(local.existing_ingress_rules[name], local.required_ingress_rules[name]) :
      join("|", [
        upper(rule.protocol),
        tostring(try(rule.port, 0)),
        tostring(try(rule.from_port, 0)),
        tostring(try(rule.to_port, 0)),
        join(",", sort(try(rule.v4_cidr_blocks, []))),
        join(",", sort(try(rule.v6_cidr_blocks, []))),
        try(rule.predefined_target, ""),
        try(rule.security_group_id, ""),
      ]) => rule
    })
  }

  instance_security_group_ids = {
    for name, instance in data.yandex_compute_instance.existing : name => sort(distinct(concat(
      [
        for group_id in tolist(try(instance.network_interface[0].security_group_ids, [])) :
        group_id if group_id != var.nodes[name].security_group_id
      ],
      [yandex_vpc_security_group.whitelist_entry[name].id],
    )))
  }

  vpn_nodes = {
    for name, instance in yandex_compute_instance.whitelist_entry : name => {
      public_ip       = yandex_vpc_address.whitelist_entry[name].external_ipv4_address[0].address
      channel         = try(var.nodes[name].channel, "prod")
      ssh_user        = try(var.nodes[name].ssh_user, "root")
      ssh_port        = try(var.nodes[name].ssh_port, 22)
      ssh_key_ref     = try(var.nodes[name].ssh_key_ref, "default")
      enabled         = try(var.nodes[name].enabled, true)
      provider        = "yandex-compute"
      region          = trimspace(try(var.nodes[name].region, "")) != "" ? try(var.nodes[name].region, "") : instance.zone
      platform_region = trimspace(try(var.nodes[name].platform_region, "")) != "" ? try(var.nodes[name].platform_region, "") : "ru"
      traffic_role    = "whitelist_entry"
    }
  }
}

resource "yandex_vpc_address" "whitelist_entry" {
  for_each = var.nodes

  name                = trimspace(try(data.yandex_vpc_address.existing[each.key].name, "")) != "" ? data.yandex_vpc_address.existing[each.key].name : null
  description         = trimspace(try(data.yandex_vpc_address.existing[each.key].description, "")) != "" ? data.yandex_vpc_address.existing[each.key].description : null
  folder_id           = try(data.yandex_vpc_address.existing[each.key].folder_id, null)
  deletion_protection = try(each.value.prevent_destroy, true)
  labels = merge(
    try(data.yandex_vpc_address.existing[each.key].labels, {}),
    {
      managed_by   = "terraform"
      role         = "vpn"
      traffic_role = "whitelist_entry"
      peer_name    = each.key
    },
    each.value.labels,
  )

  external_ipv4_address {
    zone_id = data.yandex_vpc_address.existing[each.key].external_ipv4_address[0].zone_id
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "yandex_vpc_security_group" "whitelist_entry" {
  for_each = var.nodes

  name        = trimspace(try(data.yandex_vpc_security_group.existing[each.key].name, "")) != "" ? data.yandex_vpc_security_group.existing[each.key].name : null
  description = trimspace(try(data.yandex_vpc_security_group.existing[each.key].description, "")) != "" ? data.yandex_vpc_security_group.existing[each.key].description : null
  folder_id   = try(data.yandex_vpc_security_group.existing[each.key].folder_id, null)
  network_id  = data.yandex_vpc_security_group.existing[each.key].network_id
  labels = merge(
    try(data.yandex_vpc_security_group.existing[each.key].labels, {}),
    {
      managed_by   = "terraform"
      role         = "vpn"
      traffic_role = "whitelist_entry"
      peer_name    = each.key
    },
    each.value.labels,
  )

  dynamic "ingress" {
    for_each = local.merged_ingress_rules[each.key]
    content {
      description       = ingress.value.description
      labels            = ingress.value.labels
      protocol          = ingress.value.protocol
      port              = ingress.value.port
      from_port         = ingress.value.from_port
      to_port           = ingress.value.to_port
      v4_cidr_blocks    = ingress.value.v4_cidr_blocks
      v6_cidr_blocks    = ingress.value.v6_cidr_blocks
      predefined_target = ingress.value.predefined_target
      security_group_id = ingress.value.security_group_id
    }
  }

  dynamic "egress" {
    for_each = local.existing_egress_rules[each.key]
    content {
      description       = egress.value.description
      labels            = egress.value.labels
      protocol          = egress.value.protocol
      port              = egress.value.port
      from_port         = egress.value.from_port
      to_port           = egress.value.to_port
      v4_cidr_blocks    = egress.value.v4_cidr_blocks
      v6_cidr_blocks    = egress.value.v6_cidr_blocks
      predefined_target = egress.value.predefined_target
      security_group_id = egress.value.security_group_id
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "yandex_compute_instance" "whitelist_entry" {
  for_each = var.nodes

  name                     = data.yandex_compute_instance.existing[each.key].name
  hostname                 = trimspace(try(data.yandex_compute_instance.existing[each.key].hostname, "")) != "" ? data.yandex_compute_instance.existing[each.key].hostname : null
  description              = trimspace(try(data.yandex_compute_instance.existing[each.key].description, "")) != "" ? data.yandex_compute_instance.existing[each.key].description : null
  folder_id                = try(data.yandex_compute_instance.existing[each.key].folder_id, null)
  zone                     = data.yandex_compute_instance.existing[each.key].zone
  platform_id              = data.yandex_compute_instance.existing[each.key].platform_id
  service_account_id       = trimspace(try(data.yandex_compute_instance.existing[each.key].service_account_id, "")) != "" ? data.yandex_compute_instance.existing[each.key].service_account_id : null
  maintenance_policy       = trimspace(try(data.yandex_compute_instance.existing[each.key].maintenance_policy, "")) != "" ? data.yandex_compute_instance.existing[each.key].maintenance_policy : null
  maintenance_grace_period = trimspace(try(data.yandex_compute_instance.existing[each.key].maintenance_grace_period, "")) != "" ? data.yandex_compute_instance.existing[each.key].maintenance_grace_period : null
  labels = merge(
    try(data.yandex_compute_instance.existing[each.key].labels, {}),
    {
      managed_by   = "terraform"
      role         = "vpn"
      traffic_role = "whitelist_entry"
      peer_name    = each.key
    },
    each.value.labels,
  )
  metadata = merge(
    try(data.yandex_compute_instance.existing[each.key].metadata, {}),
    {
      role         = "vpn"
      traffic-role = "whitelist_entry"
      peer-name    = each.key
    },
    each.value.metadata,
  )

  resources {
    cores         = data.yandex_compute_instance.existing[each.key].resources[0].cores
    memory        = data.yandex_compute_instance.existing[each.key].resources[0].memory
    core_fraction = try(data.yandex_compute_instance.existing[each.key].resources[0].core_fraction, null)
    gpus          = try(data.yandex_compute_instance.existing[each.key].resources[0].gpus, null)
  }

  boot_disk {
    auto_delete = try(data.yandex_compute_instance.existing[each.key].boot_disk[0].auto_delete, null)
    device_name = try(data.yandex_compute_instance.existing[each.key].boot_disk[0].device_name, null)
    disk_id     = data.yandex_compute_instance.existing[each.key].boot_disk[0].disk_id
    mode        = try(data.yandex_compute_instance.existing[each.key].boot_disk[0].mode, null)
  }

  dynamic "network_interface" {
    for_each = data.yandex_compute_instance.existing[each.key].network_interface
    content {
      index              = try(network_interface.value.index, null)
      subnet_id          = network_interface.value.subnet_id
      ip_address         = try(network_interface.value.ip_address, null)
      ipv4               = true
      nat                = trimspace(try(network_interface.value.nat_ip_address, "")) != ""
      nat_ip_address     = network_interface.key == 0 ? yandex_vpc_address.whitelist_entry[each.key].external_ipv4_address[0].address : try(network_interface.value.nat_ip_address, null)
      security_group_ids = network_interface.key == 0 ? local.instance_security_group_ids[each.key] : tolist(try(network_interface.value.security_group_ids, []))
    }
  }

  dynamic "metadata_options" {
    for_each = length(try(data.yandex_compute_instance.existing[each.key].metadata_options, [])) > 0 ? [data.yandex_compute_instance.existing[each.key].metadata_options[0]] : []
    content {
      aws_v1_http_endpoint = try(metadata_options.value.aws_v1_http_endpoint, null)
      aws_v1_http_token    = try(metadata_options.value.aws_v1_http_token, null)
      gce_http_endpoint    = try(metadata_options.value.gce_http_endpoint, null)
      gce_http_token       = try(metadata_options.value.gce_http_token, null)
    }
  }

  dynamic "filesystem" {
    for_each = try(data.yandex_compute_instance.existing[each.key].filesystem, [])
    content {
      device_name   = try(filesystem.value.device_name, null)
      filesystem_id = filesystem.value.filesystem_id
      mode          = try(filesystem.value.mode, null)
    }
  }

  dynamic "secondary_disk" {
    for_each = try(data.yandex_compute_instance.existing[each.key].secondary_disk, [])
    content {
      auto_delete = try(secondary_disk.value.auto_delete, null)
      device_name = try(secondary_disk.value.device_name, null)
      disk_id     = secondary_disk.value.disk_id
      mode        = try(secondary_disk.value.mode, null)
    }
  }

  dynamic "local_disk" {
    for_each = try(data.yandex_compute_instance.existing[each.key].local_disk, [])
    content {
      kms_key_id = try(local_disk.value.kms_key_id, null)
      size_bytes = local_disk.value.size_bytes
    }
  }

  dynamic "scheduling_policy" {
    for_each = length(try(data.yandex_compute_instance.existing[each.key].scheduling_policy, [])) > 0 ? [data.yandex_compute_instance.existing[each.key].scheduling_policy[0]] : []
    content {
      preemptible = try(scheduling_policy.value.preemptible, false)
    }
  }

  dynamic "placement_policy" {
    for_each = length(try(data.yandex_compute_instance.existing[each.key].placement_policy, [])) > 0 ? [data.yandex_compute_instance.existing[each.key].placement_policy[0]] : []
    content {
      placement_group_id        = try(placement_policy.value.placement_group_id, null)
      placement_group_partition = try(placement_policy.value.placement_group_partition, null)
      host_affinity_rules       = try(placement_policy.value.host_affinity_rules, [])
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
