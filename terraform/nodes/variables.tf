variable "vpn_nodes" {
  description = "Desired VPN nodes keyed by peer name. Public IP is required."
  type = map(object({
    public_ip = string
    channel   = optional(string, "prod")
    ssh_user  = optional(string, "root")
    ssh_port  = optional(number, 22)
    enabled   = optional(bool, true)
    provider  = optional(string, "api")
    region    = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for peer_name, node in var.vpn_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", peer_name))
        && length(trimspace(node.public_ip)) > 0
        && contains(["prod", "dev"], node.channel)
        && node.ssh_port > 0
      )
    ])
    error_message = "vpn_nodes must use valid peer names, non-empty public_ip, channel in [prod,dev], and ssh_port > 0."
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

variable "provider_api_enabled" {
  description = "Enable provider API catalog enrichment for VPN nodes (HostVDS)."
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
  description = "HostVDS VPN nodes keyed by peer name (server_id references provider object id)."
  type = map(object({
    server_id = string
    channel   = optional(string, "prod")
    ssh_user  = optional(string, "root")
    ssh_port  = optional(number, 22)
    enabled   = optional(bool, true)
    region    = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for peer_name, node in var.hostvds_vpn_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", peer_name))
        && length(trimspace(node.server_id)) > 0
        && contains(["prod", "dev"], node.channel)
        && node.ssh_port > 0
      )
    ])
    error_message = "hostvds_vpn_nodes entries must include valid peer_name, non-empty server_id, channel in [prod,dev], and ssh_port > 0."
  }
}

variable "hostvds_provisioned_vpn_nodes" {
  description = "HostVDS VPN nodes to create/destroy via OpenStack."
  type = map(object({
    name              = optional(string, "")
    image_id          = string
    flavor_id         = string
    network_ids       = list(string)
    key_pair          = optional(string, "")
    security_groups   = optional(list(string), [])
    availability_zone = optional(string, "")
    user_data         = optional(string, "")
    metadata          = optional(map(string), {})
    channel           = optional(string, "prod")
    ssh_user          = optional(string, "root")
    ssh_port          = optional(number, 22)
    enabled           = optional(bool, true)
    region            = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for peer_name, node in var.hostvds_provisioned_vpn_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", peer_name))
        && length(trimspace(node.image_id)) > 0
        && length(trimspace(node.flavor_id)) > 0
        && length(node.network_ids) > 0
        && contains(["prod", "dev"], node.channel)
        && node.ssh_port > 0
      )
    ])
    error_message = "hostvds_provisioned_vpn_nodes entries must include valid peer_name, image_id, flavor_id, at least one network_id, channel in [prod,dev], ssh_port > 0."
  }
}
