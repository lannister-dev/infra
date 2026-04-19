terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
    null = {
      source = "hashicorp/null"
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
      length(node.node_exporter_ingress_cidrs) > 0 ? [
        {
          description       = "Allow node-exporter (prometheus scrape)"
          labels            = {}
          protocol          = "TCP"
          port              = 9100
          from_port         = null
          to_port           = null
          v4_cidr_blocks    = sort(node.node_exporter_ingress_cidrs)
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

# =======================================================================
# UFW (on-VM firewall) for monitoring scrape endpoints
#
# YC Ubuntu images ship with ufw default-DROP on INPUT. Security Group at
# the cloud edge is necessary but not sufficient — the kernel drops the
# SYN despite an allow in SG. For each node whose kubelet_/
# node_exporter_ingress_cidrs are set, we open matching ufw rules through
# `yc compute ssh`. Idempotent (ufw allow is a no-op if the rule exists).
#
# Triggers re-run when either CIDR list changes, so changing the
# Prometheus host IP in catalog.auto.tfvars is enough to apply.
# =======================================================================

locals {
  ufw_targets = {
    for name, node in var.nodes : name => {
      instance_id    = node.mode == "adopt" ? yandex_compute_instance.adopted[name].id : yandex_compute_instance.created[name].id
      kubelet_cidrs  = node.kubelet_ingress_cidrs
      exporter_cidrs = node.node_exporter_ingress_cidrs
    }
    if length(node.kubelet_ingress_cidrs) + length(node.node_exporter_ingress_cidrs) > 0
  }
}

resource "null_resource" "ufw_monitoring" {
  for_each = local.ufw_targets

  triggers = {
    instance_id    = each.value.instance_id
    kubelet_cidrs  = join(",", sort(each.value.kubelet_cidrs))
    exporter_cidrs = join(",", sort(each.value.exporter_cidrs))
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      rules=()
      for cidr in ${join(" ", each.value.kubelet_cidrs)}; do
        rules+=("sudo ufw allow from $cidr to any port 10250 proto tcp")
      done
      for cidr in ${join(" ", each.value.exporter_cidrs)}; do
        rules+=("sudo ufw allow from $cidr to any port 9100 proto tcp")
      done
      if [ $${#rules[@]} -eq 0 ]; then exit 0; fi
      cmd=$(printf '%s; ' "$${rules[@]}")
      id_arg=""
      if [ -n "${var.ssh_identity_file}" ]; then
        id_arg="--identity-file ${var.ssh_identity_file}"
      fi
      yc compute ssh --id ${each.value.instance_id} $id_arg -- "$cmd" || exit $?
    EOT
    interpreter = ["bash", "-c"]
  }
}

# =======================================================================
# Netplan: expose the 1:1 NAT public IP as a /32 alias on eth0.
#
# On YC, eth0 carries only the private VPC IP (e.g. 10.130.0.14) — the
# public address (e.g. 158.160.231.247) lives on the provider fabric and
# is delivered to the VM via 1:1 NAT. Kubelet's `--node-ip=<public>`
# validates against locally-configured addresses; without the alias it
# silently falls back to the private IP, which is unreachable from the
# rest of the cluster.
#
# Adding the public IP as a /32 alias keeps eth0's primary IP (and thus
# outbound source selection) intact, while letting kubelet — and any
# other process that binds explicitly — accept `158.160.231.247` as a
# local address. Paired with k3s-agent args:
#   --node-ip=<public> --node-external-ip=<public> --flannel-iface=eth0
# the node reports the public IP as InternalIP and behaves identically
# to non-NAT'd VPN nodes (timeweb/hostvds) as far as the cluster is
# concerned — no scrape-path workarounds required.
# =======================================================================

locals {
  netplan_targets = {
    for name, node in var.nodes : name => {
      instance_id = node.mode == "adopt" ? yandex_compute_instance.adopted[name].id : yandex_compute_instance.created[name].id
      public_ip   = local.nodes_output[name].public_ip
    }
  }
}

resource "null_resource" "netplan_public_ip_alias" {
  for_each = local.netplan_targets

  triggers = {
    instance_id = each.value.instance_id
    public_ip   = each.value.public_ip
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      id_arg=""
      if [ -n "${var.ssh_identity_file}" ]; then
        id_arg="--identity-file ${var.ssh_identity_file}"
      fi
      remote=$(cat <<'REMOTE'
set -euo pipefail
sudo tee /etc/netplan/60-k3s-public-alias.yaml >/dev/null <<NETPLAN
# Managed by terraform/yandex-vpn — do not edit by hand.
# Exposes the 1:1 NAT public IP as a /32 alias on eth0 so kubelet
# --node-ip=<public> passes its local-address check. Outbound routing
# is unaffected: eth0 primary IP is still the source for default route.
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - PUBLIC_IP/32
NETPLAN
sudo chmod 0600 /etc/netplan/60-k3s-public-alias.yaml
sudo netplan apply
REMOTE
)
      remote="$${remote//PUBLIC_IP/${each.value.public_ip}}"
      yc compute ssh --id ${each.value.instance_id} $id_arg -- "$remote"
    EOT
    interpreter = ["bash", "-c"]
  }
}
