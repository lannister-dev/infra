terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

locals {
  adopt_nodes  = { for name, node in var.nodes : name => node if node.mode == "adopt" }
  create_nodes = { for name, node in var.nodes : name => node if node.mode == "create" }

  required_ingress_rules = {
    for name, node in var.nodes : name => concat(
      [
        {
          description       = "Allow SSH"
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
          description       = "Allow HTTPS"
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
      ],
      length(node.kubelet_ingress_cidrs) > 0 ? [
        {
          description       = "Allow kubelet (metrics-server scrape)"
          labels            = {}
          protocol          = "TCP"
          port              = 10250
          from_port         = null
          to_port           = null
          v4_cidr_blocks    = sort(node.kubelet_ingress_cidrs)
          v6_cidr_blocks    = []
          predefined_target = null
          security_group_id = null
        },
      ] : [],
    )
  }

  # ---- adopt mode: mirror existing resource configuration ---------------
  # YC provider returns -1 as a sentinel for "unset" port/from_port/to_port;
  # normalise it to null so rules match `required_ingress_rules` (which uses
  # null) during dedup.
  existing_ingress_rules = {
    for name, group in data.yandex_vpc_security_group.adopted : name => [
      for rule in group.ingress : {
        description       = try(rule.description, null)
        labels            = try(rule.labels, {})
        protocol          = rule.protocol
        port              = try(rule.port, null) != null && rule.port != -1 ? rule.port : null
        from_port         = try(rule.from_port, null) != null && rule.from_port != -1 ? rule.from_port : null
        to_port           = try(rule.to_port, null) != null && rule.to_port != -1 ? rule.to_port : null
        v4_cidr_blocks    = sort(try(rule.v4_cidr_blocks, []))
        v6_cidr_blocks    = sort(try(rule.v6_cidr_blocks, []))
        predefined_target = try(rule.predefined_target, null)
        security_group_id = try(rule.security_group_id, null)
      }
    ]
  }

  existing_egress_rules = {
    for name, group in data.yandex_vpc_security_group.adopted : name => [
      for rule in group.egress : {
        description       = try(rule.description, null)
        labels            = try(rule.labels, {})
        protocol          = rule.protocol
        port              = try(rule.port, null) != null && rule.port != -1 ? rule.port : null
        from_port         = try(rule.from_port, null) != null && rule.from_port != -1 ? rule.from_port : null
        to_port           = try(rule.to_port, null) != null && rule.to_port != -1 ? rule.to_port : null
        v4_cidr_blocks    = sort(try(rule.v4_cidr_blocks, []))
        v6_cidr_blocks    = sort(try(rule.v6_cidr_blocks, []))
        predefined_target = try(rule.predefined_target, null)
        security_group_id = try(rule.security_group_id, null)
      }
    ]
  }

  # Dedup by a composite key. Existing rules come first in `concat` so they
  # "win" on collisions — we prefer keeping the current YC state verbatim.
  merged_adopt_ingress_rules = {
    for name, node in local.adopt_nodes : name => [
      for group in values({
        for rule in concat(local.existing_ingress_rules[name], local.required_ingress_rules[name]) :
        join("|", [
          rule.protocol != null && trimspace(rule.protocol) != "" ? upper(rule.protocol) : "ANY",
          tostring(rule.port != null ? rule.port : 0),
          tostring(rule.from_port != null ? rule.from_port : 0),
          tostring(rule.to_port != null ? rule.to_port : 0),
          join(",", sort(try(rule.v4_cidr_blocks, []))),
          join(",", sort(try(rule.v6_cidr_blocks, []))),
          rule.predefined_target != null ? rule.predefined_target : "",
          rule.security_group_id != null ? rule.security_group_id : "",
        ]) => rule...
      }) : group[0]
    ]
  }

  adopt_instance_security_group_ids = {
    for name, instance in data.yandex_compute_instance.adopted : name => sort(distinct(concat(
      [
        for group_id in tolist(try(instance.network_interface[0].security_group_ids, [])) :
        group_id if group_id != local.adopt_nodes[name].security_group_id
      ],
      [yandex_vpc_security_group.adopted[name].id],
    )))
  }

  # ---- normalized output ------------------------------------------------
  nodes_output = merge(
    {
      for name, _ in local.adopt_nodes : name => {
        mode       = "adopt"
        public_ip  = yandex_vpc_address.adopted[name].external_ipv4_address[0].address
        zone       = yandex_compute_instance.adopted[name].zone
        instance   = yandex_compute_instance.adopted[name].id
        address    = yandex_vpc_address.adopted[name].id
        security_g = yandex_vpc_security_group.adopted[name].id
      }
    },
    {
      for name, _ in local.create_nodes : name => {
        mode       = "create"
        public_ip  = yandex_vpc_address.created[name].external_ipv4_address[0].address
        zone       = yandex_compute_instance.created[name].zone
        instance   = yandex_compute_instance.created[name].id
        address    = yandex_vpc_address.created[name].id
        security_g = yandex_vpc_security_group.created[name].id
      }
    },
  )
}

# =======================================================================
# Adopt mode
# =======================================================================

data "yandex_compute_instance" "adopted" {
  for_each    = local.adopt_nodes
  instance_id = each.value.instance_id
}

data "yandex_vpc_address" "adopted" {
  for_each   = local.adopt_nodes
  address_id = each.value.address_id
}

data "yandex_vpc_security_group" "adopted" {
  for_each          = local.adopt_nodes
  security_group_id = each.value.security_group_id
}

resource "yandex_vpc_address" "adopted" {
  for_each = local.adopt_nodes

  name                = try(data.yandex_vpc_address.adopted[each.key].name, null) != null ? (trimspace(data.yandex_vpc_address.adopted[each.key].name) != "" ? data.yandex_vpc_address.adopted[each.key].name : null) : null
  description         = try(data.yandex_vpc_address.adopted[each.key].description, null) != null ? (trimspace(data.yandex_vpc_address.adopted[each.key].description) != "" ? data.yandex_vpc_address.adopted[each.key].description : null) : null
  folder_id           = try(data.yandex_vpc_address.adopted[each.key].folder_id, null)
  deletion_protection = try(each.value.prevent_destroy, true)
  labels = merge(
    try(data.yandex_vpc_address.adopted[each.key].labels, {}),
    {
      managed_by = "terraform"
      role       = "vpn"
      peer_name  = each.key
    },
    each.value.labels,
  )

  external_ipv4_address {
    zone_id = data.yandex_vpc_address.adopted[each.key].external_ipv4_address[0].zone_id
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "yandex_vpc_security_group" "adopted" {
  for_each = local.adopt_nodes

  name        = try(data.yandex_vpc_security_group.adopted[each.key].name, null) != null ? (trimspace(data.yandex_vpc_security_group.adopted[each.key].name) != "" ? data.yandex_vpc_security_group.adopted[each.key].name : null) : null
  description = try(data.yandex_vpc_security_group.adopted[each.key].description, null) != null ? (trimspace(data.yandex_vpc_security_group.adopted[each.key].description) != "" ? data.yandex_vpc_security_group.adopted[each.key].description : null) : null
  folder_id   = try(data.yandex_vpc_security_group.adopted[each.key].folder_id, null)
  network_id  = data.yandex_vpc_security_group.adopted[each.key].network_id
  labels = merge(
    try(data.yandex_vpc_security_group.adopted[each.key].labels, {}),
    {
      managed_by = "terraform"
      role       = "vpn"
      peer_name  = each.key
    },
    each.value.labels,
  )

  dynamic "ingress" {
    for_each = local.merged_adopt_ingress_rules[each.key]
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

resource "yandex_compute_instance" "adopted" {
  for_each = local.adopt_nodes

  name                     = data.yandex_compute_instance.adopted[each.key].name
  hostname                 = try(data.yandex_compute_instance.adopted[each.key].hostname, null) != null ? (trimspace(data.yandex_compute_instance.adopted[each.key].hostname) != "" ? data.yandex_compute_instance.adopted[each.key].hostname : null) : null
  description              = try(data.yandex_compute_instance.adopted[each.key].description, null) != null ? (trimspace(data.yandex_compute_instance.adopted[each.key].description) != "" ? data.yandex_compute_instance.adopted[each.key].description : null) : null
  folder_id                = try(data.yandex_compute_instance.adopted[each.key].folder_id, null)
  zone                     = data.yandex_compute_instance.adopted[each.key].zone
  platform_id              = data.yandex_compute_instance.adopted[each.key].platform_id
  service_account_id       = try(data.yandex_compute_instance.adopted[each.key].service_account_id, null) != null ? (trimspace(data.yandex_compute_instance.adopted[each.key].service_account_id) != "" ? data.yandex_compute_instance.adopted[each.key].service_account_id : null) : null
  maintenance_policy       = try(data.yandex_compute_instance.adopted[each.key].maintenance_policy, null) != null ? (trimspace(data.yandex_compute_instance.adopted[each.key].maintenance_policy) != "" ? data.yandex_compute_instance.adopted[each.key].maintenance_policy : null) : null
  maintenance_grace_period = try(data.yandex_compute_instance.adopted[each.key].maintenance_grace_period, null) != null ? (trimspace(data.yandex_compute_instance.adopted[each.key].maintenance_grace_period) != "" ? data.yandex_compute_instance.adopted[each.key].maintenance_grace_period : null) : null
  labels = merge(
    try(data.yandex_compute_instance.adopted[each.key].labels, {}),
    {
      managed_by = "terraform"
      role       = "vpn"
      peer_name  = each.key
    },
    each.value.labels,
  )
  metadata = merge(
    try(data.yandex_compute_instance.adopted[each.key].metadata, {}),
    {
      role      = "vpn"
      peer-name = each.key
    },
    each.value.metadata,
  )

  resources {
    cores         = data.yandex_compute_instance.adopted[each.key].resources[0].cores
    memory        = data.yandex_compute_instance.adopted[each.key].resources[0].memory
    core_fraction = try(data.yandex_compute_instance.adopted[each.key].resources[0].core_fraction, null)
    gpus          = try(data.yandex_compute_instance.adopted[each.key].resources[0].gpus, null)
  }

  boot_disk {
    auto_delete = try(data.yandex_compute_instance.adopted[each.key].boot_disk[0].auto_delete, null)
    device_name = try(data.yandex_compute_instance.adopted[each.key].boot_disk[0].device_name, null)
    disk_id     = data.yandex_compute_instance.adopted[each.key].boot_disk[0].disk_id
    mode        = try(data.yandex_compute_instance.adopted[each.key].boot_disk[0].mode, null)
  }

  dynamic "network_interface" {
    for_each = data.yandex_compute_instance.adopted[each.key].network_interface
    content {
      index              = try(network_interface.value.index, null)
      subnet_id          = network_interface.value.subnet_id
      ip_address         = try(network_interface.value.ip_address, null)
      ipv4               = true
      nat                = try(network_interface.value.nat_ip_address, null) != null ? trimspace(network_interface.value.nat_ip_address) != "" : false
      nat_ip_address     = network_interface.key == 0 ? yandex_vpc_address.adopted[each.key].external_ipv4_address[0].address : try(network_interface.value.nat_ip_address, null)
      security_group_ids = network_interface.key == 0 ? local.adopt_instance_security_group_ids[each.key] : tolist(try(network_interface.value.security_group_ids, []))
    }
  }

  dynamic "metadata_options" {
    for_each = length(try(data.yandex_compute_instance.adopted[each.key].metadata_options, [])) > 0 ? [data.yandex_compute_instance.adopted[each.key].metadata_options[0]] : []
    content {
      aws_v1_http_endpoint = try(metadata_options.value.aws_v1_http_endpoint, null)
      aws_v1_http_token    = try(metadata_options.value.aws_v1_http_token, null)
      gce_http_endpoint    = try(metadata_options.value.gce_http_endpoint, null)
      gce_http_token       = try(metadata_options.value.gce_http_token, null)
    }
  }

  dynamic "filesystem" {
    for_each = try(data.yandex_compute_instance.adopted[each.key].filesystem, [])
    content {
      device_name   = try(filesystem.value.device_name, null)
      filesystem_id = filesystem.value.filesystem_id
      mode          = try(filesystem.value.mode, null)
    }
  }

  dynamic "secondary_disk" {
    for_each = try(data.yandex_compute_instance.adopted[each.key].secondary_disk, [])
    content {
      auto_delete = try(secondary_disk.value.auto_delete, null)
      device_name = try(secondary_disk.value.device_name, null)
      disk_id     = secondary_disk.value.disk_id
      mode        = try(secondary_disk.value.mode, null)
    }
  }

  dynamic "local_disk" {
    for_each = try(data.yandex_compute_instance.adopted[each.key].local_disk, [])
    content {
      kms_key_id = try(local_disk.value.kms_key_id, null)
      size_bytes = local_disk.value.size_bytes
    }
  }

  dynamic "scheduling_policy" {
    for_each = length(try(data.yandex_compute_instance.adopted[each.key].scheduling_policy, [])) > 0 ? [data.yandex_compute_instance.adopted[each.key].scheduling_policy[0]] : []
    content {
      preemptible = try(scheduling_policy.value.preemptible, false)
    }
  }

  dynamic "placement_policy" {
    for_each = length(try(data.yandex_compute_instance.adopted[each.key].placement_policy, [])) > 0 ? [data.yandex_compute_instance.adopted[each.key].placement_policy[0]] : []
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

# =======================================================================
# Create mode
# =======================================================================

resource "yandex_vpc_address" "created" {
  for_each = local.create_nodes

  name                = each.key
  deletion_protection = try(each.value.prevent_destroy, false)
  labels = merge(
    {
      managed_by = "terraform"
      role       = "vpn"
      peer_name  = each.key
    },
    each.value.labels,
  )

  external_ipv4_address {
    zone_id = each.value.zone
  }
}

resource "yandex_vpc_security_group" "created" {
  for_each = local.create_nodes

  name       = each.key
  network_id = each.value.network_id
  labels = merge(
    {
      managed_by = "terraform"
      role       = "vpn"
      peer_name  = each.key
    },
    each.value.labels,
  )

  dynamic "ingress" {
    for_each = local.required_ingress_rules[each.key]
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

  egress {
    description    = "Allow all egress"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_compute_instance" "created" {
  for_each = local.create_nodes

  name        = each.key
  hostname    = each.key
  zone        = each.value.zone
  platform_id = each.value.platform_id
  labels = merge(
    {
      managed_by = "terraform"
      role       = "vpn"
      peer_name  = each.key
    },
    each.value.labels,
  )
  metadata = merge(
    {
      role      = "vpn"
      peer-name = each.key
    },
    length(trimspace(coalesce(each.value.ssh_public_key, ""))) > 0 ? {
      "ssh-keys" = "ubuntu:${each.value.ssh_public_key}"
    } : {},
    length(trimspace(coalesce(each.value.user_data, ""))) > 0 ? {
      "user-data" = each.value.user_data
    } : {},
    each.value.metadata,
  )

  resources {
    cores  = each.value.cores
    memory = each.value.memory
  }

  boot_disk {
    initialize_params {
      image_id = each.value.image_id
      size     = each.value.disk_size
    }
  }

  network_interface {
    subnet_id          = each.value.subnet_id
    nat                = each.value.nat_enabled
    nat_ip_address     = yandex_vpc_address.created[each.key].external_ipv4_address[0].address
    security_group_ids = [yandex_vpc_security_group.created[each.key].id]
  }
}
