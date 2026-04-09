variable "infra_nodes" {
  description = "Manual infra nodes map keyed by node name."
  type = map(object({
    public_ip   = string
    role        = optional(string, "worker")
    kind        = optional(string, "prod")
    ssh_user    = optional(string, "root")
    ssh_port    = optional(number, 22)
    ssh_key_ref = optional(string, "default")
    enabled     = optional(bool, true)
    provider    = optional(string, "manual")
    region      = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, node in var.infra_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", name))
        && length(trimspace(node.public_ip)) > 0
        && contains(["manager", "worker"], node.role)
        && contains(["prod", "dev"], node.kind)
        && node.ssh_port > 0
      )
    ])
    error_message = "infra_nodes entries must use valid node names, non-empty public_ip, role in [manager,worker], kind in [prod,dev], and ssh_port > 0."
  }
}

variable "provider_api_enabled" {
  description = "Enable Timeweb API enrichment for infra nodes."
  type        = bool
  default     = false
}

variable "timeweb_compute_enabled" {
  description = "Enable Timeweb compute provisioning for infra nodes."
  type        = bool
  default     = false
}

variable "timeweb_api_url" {
  description = "Timeweb API base URL."
  type        = string
  default     = "https://api.timeweb.cloud/api/v1"
}

variable "timeweb_api_token" {
  description = "Timeweb API token."
  type        = string
  default     = ""
  sensitive   = true
}

variable "timeweb_auth_header" {
  description = "Auth header name for Timeweb API."
  type        = string
  default     = "Authorization"
}

variable "timeweb_auth_scheme" {
  description = "Auth scheme prefix for Timeweb API token."
  type        = string
  default     = "Bearer"
}

variable "timeweb_endpoint_template" {
  description = "Timeweb endpoint template with {server_id} placeholder."
  type        = string
  default     = "/servers/{server_id}"
}

variable "timeweb_infra_nodes" {
  description = "Timeweb infra nodes keyed by node name."
  type = map(object({
    server_id   = string
    role        = optional(string, "worker")
    kind        = optional(string, "prod")
    ssh_user    = optional(string, "root")
    ssh_port    = optional(number, 22)
    ssh_key_ref = optional(string, "default")
    enabled     = optional(bool, true)
    region      = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, node in var.timeweb_infra_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", name))
        && length(trimspace(node.server_id)) > 0
        && contains(["manager", "worker"], node.role)
        && contains(["prod", "dev"], node.kind)
        && node.ssh_port > 0
      )
    ])
    error_message = "timeweb_infra_nodes entries must use valid node names, non-empty server_id, role in [manager,worker], kind in [prod,dev], and ssh_port > 0."
  }
}

variable "timeweb_provisioned_infra_nodes" {
  description = "Timeweb infra nodes to create/destroy."
  type = map(object({
    name              = optional(string, "")
    os_id             = number
    preset_id         = optional(number)
    location          = optional(string, "")
    availability_zone = optional(string, "")
    preset_type       = optional(string, "premium")
    disk_type         = optional(string, "")
    cpu               = optional(number)
    ram               = optional(number)
    disk              = optional(number)
    project_id        = optional(number)
    software_id       = optional(number)
    ssh_keys_ids      = optional(list(number), [])
    cloud_init        = optional(string, "")
    role              = optional(string, "worker")
    kind              = optional(string, "prod")
    ssh_user          = optional(string, "root")
    ssh_port          = optional(number, 22)
    ssh_key_ref       = optional(string, "default")
    enabled           = optional(bool, true)
    region            = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, node in var.timeweb_provisioned_infra_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", name))
        && node.os_id > 0
        && contains(["manager", "worker"], node.role)
        && contains(["prod", "dev"], node.kind)
        && node.ssh_port > 0
        && (
          coalesce(node.preset_id, 0) > 0
          || (
            length(trimspace(try(node.location, ""))) > 0
            && coalesce(node.cpu, 0) > 0
            && coalesce(node.ram, 0) > 0
            && coalesce(node.disk, 0) > 0
          )
        )
      )
    ])
    error_message = "timeweb_provisioned_infra_nodes entries must use valid node names, os_id>0, and either preset_id>0 or location+cpu+ram+disk for custom config; role in [manager,worker], kind in [prod,dev], and ssh_port > 0."
  }
}

variable "inventory_output_path" {
  description = "Path to generated infra inventory file."
  type        = string
  default     = ""
}
