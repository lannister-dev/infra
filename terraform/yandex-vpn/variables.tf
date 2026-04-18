variable "yandex_token" {
  description = "Yandex Cloud IAM token. Optional when YC_TOKEN is already set in the environment. Prefer service account key file for long-lived automation."
  type        = string
  default     = ""
  sensitive   = true
}

variable "yandex_service_account_key_file" {
  description = "Path to Yandex Cloud service account authorized key JSON. Optional when YC_SERVICE_ACCOUNT_KEY_FILE is already set in the environment."
  type        = string
  default     = ""
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
  description = "Default Yandex Cloud availability zone. Optional when node entries already carry zone information."
  type        = string
  default     = ""
}

variable "yandex_vpn_nodes" {
  description = "Yandex Cloud VPN nodes. mode=adopt reuses existing resources by ID; mode=create provisions fresh VM+address+security_group."
  type = map(object({
    mode = string

    # adopt mode: references to existing resources
    instance_id       = optional(string, "")
    address_id        = optional(string, "")
    security_group_id = optional(string, "")

    # create mode: spec for fresh VM
    zone           = optional(string, "")
    subnet_id      = optional(string, "")
    network_id     = optional(string, "")
    image_id       = optional(string, "")
    platform_id    = optional(string, "standard-v3")
    cores          = optional(number, 2)
    memory         = optional(number, 2)
    disk_size      = optional(number, 20)
    nat_enabled    = optional(bool, true)
    ssh_public_key = optional(string, "")
    user_data      = optional(string, "")

    # common
    labels              = optional(map(string), {})
    metadata            = optional(map(string), {})
    ssh_ingress_cidrs     = optional(list(string), ["0.0.0.0/0"])
    https_ingress_cidrs   = optional(list(string), ["0.0.0.0/0"])
    kubelet_ingress_cidrs = optional(list(string), [])
    prevent_destroy       = optional(bool, true)
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, node in var.yandex_vpn_nodes : (
        can(regex("^[a-zA-Z0-9._-]+$", name))
        && contains(["adopt", "create"], node.mode)
        && (
          node.mode != "adopt"
          || (length(trimspace(node.instance_id)) > 0
            && length(trimspace(node.address_id)) > 0
          && length(trimspace(node.security_group_id)) > 0)
        )
        && (
          node.mode != "create"
          || (length(trimspace(coalesce(node.image_id, ""))) > 0
            && length(trimspace(coalesce(node.subnet_id, ""))) > 0
          && length(trimspace(coalesce(node.network_id, ""))) > 0)
        )
      )
    ])
    error_message = "Each yandex_vpn_nodes entry must have a valid name, mode in [adopt,create], adopt requires instance_id+address_id+security_group_id, create requires image_id+subnet_id+network_id."
  }
}
