variable "vpn_nodes" {
  description = "Desired VPN nodes keyed by peer name. Public IP is required."
  type = map(object({
    public_ip       = string
    channel         = optional(string, "prod")
    ssh_user        = optional(string, "root")
    ssh_port        = optional(number, 22)
    ssh_key_ref     = optional(string, "default")
    enabled         = optional(bool, true)
    provider        = optional(string, "api")
    region          = optional(string, "")
    platform_region = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for peer_name, node in var.vpn_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", peer_name))
        && length(trimspace(node.public_ip)) > 0
        && contains(["prod", "dev"], node.channel)
        && node.ssh_port > 0
        && can(regex("^[a-zA-Z0-9._-]+$", node.ssh_key_ref))
      )
    ])
    error_message = "vpn_nodes must use valid peer names, non-empty public_ip, channel in [prod,dev], ssh_port > 0, and ssh_key_ref matching [a-zA-Z0-9._-]+."
  }
}

variable "inventory_output_path" {
  description = "Path to generated Ansible inventory variables file."
  type        = string
  default     = ""
}

variable "allow_empty_vpn_nodes" {
  description = "Allow empty enabled VPN node set (dangerous; use only for intentional full decommission)."
  type        = bool
  default     = false
}

variable "yandex_token" {
  description = "Yandex Cloud IAM token. Optional when YC_TOKEN is already set in the environment."
  type        = string
  default     = ""
  sensitive   = true
}

variable "yandex_cloud_id" {
  description = "Yandex Cloud cloud ID. Optional when YC_CLOUD_ID is already set in the environment."
  type        = string
  default     = ""
}

variable "yandex_folder_id" {
  description = "Yandex Cloud folder ID. Optional when YC_FOLDER_ID is already set in the environment."
  type        = string
  default     = ""
}

variable "yandex_zone" {
  description = "Default Yandex Cloud availability zone. Optional when resource data already carries zone information."
  type        = string
  default     = ""
}

variable "provider_api_enabled" {
  description = "Legacy switch to force provider API catalog enrichment. Preferred flow is provider_api_vpn_nodes."
  type        = bool
  default     = false
}

variable "hostvds_compute_enabled" {
  description = "Enable HostVDS compute provisioning via OpenStack."
  type        = bool
  default     = false
}

variable "hostvds_os_auth_url" {
  description = "HostVDS OpenStack auth URL (OS_AUTH_URL)."
  type        = string
  default     = ""
}

variable "hostvds_os_username" {
  description = "HostVDS OpenStack username (OS_USERNAME)."
  type        = string
  default     = ""
}

variable "hostvds_os_password" {
  description = "HostVDS OpenStack password (OS_PASSWORD)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "hostvds_os_project_name" {
  description = "HostVDS OpenStack project name (OS_PROJECT_NAME)."
  type        = string
  default     = ""
}

variable "hostvds_os_user_domain_name" {
  description = "HostVDS OpenStack user domain name (OS_USER_DOMAIN_NAME)."
  type        = string
  default     = ""
}

variable "hostvds_os_user_domain_id" {
  description = "HostVDS OpenStack user domain id (OS_USER_DOMAIN_ID)."
  type        = string
  default     = ""
}

variable "hostvds_os_project_domain_name" {
  description = "HostVDS OpenStack project domain name (OS_PROJECT_DOMAIN_NAME)."
  type        = string
  default     = ""
}

variable "hostvds_os_project_domain_id" {
  description = "HostVDS OpenStack project domain id (OS_PROJECT_DOMAIN_ID)."
  type        = string
  default     = ""
}

variable "hostvds_os_region_name" {
  description = "HostVDS OpenStack region name (OS_REGION_NAME)."
  type        = string
  default     = ""
}

variable "hostvds_os_interface" {
  description = "HostVDS OpenStack endpoint interface (public/internal/admin)."
  type        = string
  default     = ""
}

variable "hostvds_vpn_nodes" {
  description = "Legacy HostVDS API node catalog keyed by peer name (server_id references provider object id)."
  type = map(object({
    server_id       = string
    channel         = optional(string, "prod")
    ssh_user        = optional(string, "root")
    ssh_port        = optional(number, 22)
    ssh_key_ref     = optional(string, "default")
    enabled         = optional(bool, true)
    region          = optional(string, "")
    platform_region = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for peer_name, node in var.hostvds_vpn_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", peer_name))
        && length(trimspace(node.server_id)) > 0
        && contains(["prod", "dev"], node.channel)
        && node.ssh_port > 0
        && can(regex("^[a-zA-Z0-9._-]+$", node.ssh_key_ref))
      )
    ])
    error_message = "hostvds_vpn_nodes entries must include valid peer_name, non-empty server_id, channel in [prod,dev], ssh_port > 0, and ssh_key_ref matching [a-zA-Z0-9._-]+."
  }
}

variable "provider_api_vpn_nodes" {
  description = "Provider-agnostic API node catalog keyed by peer name. Each entry selects provider + server_id."
  type = map(object({
    provider        = string
    server_id       = string
    channel         = optional(string, "prod")
    ssh_user        = optional(string, "root")
    ssh_port        = optional(number, 22)
    ssh_key_ref     = optional(string, "default")
    enabled         = optional(bool, true)
    region          = optional(string, "")
    platform_region = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for peer_name, node in var.provider_api_vpn_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", peer_name))
        && contains(["hostvds"], lower(trimspace(node.provider)))
        && length(trimspace(node.server_id)) > 0
        && contains(["prod", "dev"], node.channel)
        && node.ssh_port > 0
        && can(regex("^[a-zA-Z0-9._-]+$", node.ssh_key_ref))
      )
    ])
    error_message = "provider_api_vpn_nodes entries must include valid peer_name, provider=hostvds, non-empty server_id, channel in [prod,dev], ssh_port > 0, and ssh_key_ref matching [a-zA-Z0-9._-]+."
  }
}

variable "hostvds_provisioned_vpn_nodes" {
  description = "Legacy HostVDS compute node catalog to create/destroy via OpenStack."
  type = map(object({
    name              = optional(string, "")
    image_id          = optional(string, "")
    image_name        = optional(string, "")
    flavor_id         = optional(string, "")
    flavor_name       = optional(string, "")
    network_ids       = list(string)
    key_pair          = optional(string, "")
    security_groups   = optional(list(string), [])
    availability_zone = optional(string, "")
    user_data         = optional(string, "")
    metadata          = optional(map(string), {})
    channel           = optional(string, "prod")
    ssh_user          = optional(string, "root")
    ssh_port          = optional(number, 22)
    ssh_key_ref       = optional(string, "default")
    enabled           = optional(bool, true)
    region            = optional(string, "")
    platform_region   = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for peer_name, node in var.hostvds_provisioned_vpn_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", peer_name))
        && (length(trimspace(node.image_id)) > 0 || length(trimspace(node.image_name)) > 0)
        && (length(trimspace(node.flavor_id)) > 0 || length(trimspace(node.flavor_name)) > 0)
        && length(node.network_ids) > 0
        && contains(["prod", "dev"], node.channel)
        && node.ssh_port > 0
        && can(regex("^[a-zA-Z0-9._-]+$", node.ssh_key_ref))
      )
    ])
    error_message = "hostvds_provisioned_vpn_nodes entries must include valid peer_name, image_id/image_name, flavor_id/flavor_name, at least one network_id, channel in [prod,dev], ssh_port > 0, and ssh_key_ref matching [a-zA-Z0-9._-]+."
  }
}

variable "provider_compute_vpn_nodes" {
  description = "Provider-agnostic compute node catalog keyed by peer name. Each entry selects provider + provisioning spec."
  type = map(object({
    provider          = string
    name              = optional(string, "")
    image_id          = optional(string, "")
    image_name        = optional(string, "")
    flavor_id         = optional(string, "")
    flavor_name       = optional(string, "")
    network_ids       = optional(list(string), [])
    key_pair          = optional(string, "")
    security_groups   = optional(list(string), [])
    availability_zone = optional(string, "")
    user_data         = optional(string, "")
    metadata          = optional(map(string), {})
    channel           = optional(string, "prod")
    ssh_user          = optional(string, "root")
    ssh_port          = optional(number, 22)
    ssh_key_ref       = optional(string, "default")
    enabled           = optional(bool, true)
    region            = optional(string, "")
    platform_region   = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for peer_name, node in var.provider_compute_vpn_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", peer_name))
        && contains(["hostvds"], lower(trimspace(node.provider)))
        && (length(trimspace(node.image_id)) > 0 || length(trimspace(node.image_name)) > 0)
        && (length(trimspace(node.flavor_id)) > 0 || length(trimspace(node.flavor_name)) > 0)
        && length(node.network_ids) > 0
        && contains(["prod", "dev"], node.channel)
        && node.ssh_port > 0
        && can(regex("^[a-zA-Z0-9._-]+$", node.ssh_key_ref))
      )
    ])
    error_message = "provider_compute_vpn_nodes entries must include valid peer_name, provider=hostvds, image_id/image_name, flavor_id/flavor_name, at least one network_id, channel in [prod,dev], ssh_port > 0, and ssh_key_ref matching [a-zA-Z0-9._-]+."
  }
}

variable "yandex_whitelist_entry_nodes" {
  description = "Existing Yandex Cloud whitelist entry nodes to adopt into Terraform without recreate."
  type = map(object({
    instance_id         = string
    address_id          = string
    security_group_id   = string
    channel             = optional(string, "prod")
    ssh_user            = optional(string, "root")
    ssh_port            = optional(number, 22)
    ssh_key_ref         = optional(string, "default")
    enabled             = optional(bool, true)
    region              = optional(string, "")
    platform_region     = optional(string, "")
    labels              = optional(map(string), {})
    metadata            = optional(map(string), {})
    ssh_ingress_cidrs   = optional(list(string), ["0.0.0.0/0"])
    https_ingress_cidrs = optional(list(string), ["0.0.0.0/0"])
    prevent_destroy     = optional(bool, true)
  }))
  default = {}

  validation {
    condition = alltrue([
      for peer_name, node in var.yandex_whitelist_entry_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", peer_name))
        && length(trimspace(node.instance_id)) > 0
        && length(trimspace(node.address_id)) > 0
        && length(trimspace(node.security_group_id)) > 0
        && contains(["prod", "dev"], node.channel)
        && node.ssh_port > 0
        && can(regex("^[a-zA-Z0-9._-]+$", node.ssh_key_ref))
      )
    ])
    error_message = "yandex_whitelist_entry_nodes entries must include valid peer_name, non-empty instance_id/address_id/security_group_id, channel in [prod,dev], ssh_port > 0, and ssh_key_ref matching [a-zA-Z0-9._-]+."
  }
}
