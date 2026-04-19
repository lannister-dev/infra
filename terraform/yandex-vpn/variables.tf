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

variable "ssh_identity_file" {
  description = "Path to the private SSH key used by on-VM provisioners (netplan alias, k3s install) and by `yc compute ssh` for ufw. When `ssh_user` is also set, netplan/k3s provisioners use plain SSH over the node's public IP; this avoids YC OS-Login's requirement that the IAM username exist on the VM."
  type        = string
  default     = ""
}

variable "ssh_user" {
  description = "SSH login name for on-VM provisioners. When empty, provisioners fall back to `yc compute ssh` (which uses OS Login via the IAM profile). YC Ubuntu images typically expose `ubuntu`; hand-curated VMs may use a custom account."
  type        = string
  default     = ""
}

variable "k3s_join_token_vault_path" {
  description = "Vault KVv2 logical path (without the `data/` prefix) holding the k3s cluster join token. Must expose `token` and `url` fields — see `secret/k3s/join-token`. Set to \"\" to disable the k3s auto-install null_resource on nodes that carry `k3s_install`."
  type        = string
  default     = "secret/k3s/join-token"
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
    labels                      = optional(map(string), {})
    metadata                    = optional(map(string), {})
    ssh_ingress_cidrs           = optional(list(string), ["0.0.0.0/0"])
    https_ingress_cidrs         = optional(list(string), ["0.0.0.0/0"])
    kubelet_ingress_cidrs       = optional(list(string), [])
    node_exporter_ingress_cidrs = optional(list(string), [])
    prevent_destroy             = optional(bool, true)

    # k3s auto-install config. If set, terraform installs k3s-agent on the
    # VM via `yc compute ssh` and re-applies on any trigger change. Join
    # URL + token are read from Vault (see var.k3s_join_token_vault_path).
    # --node-ip / --node-external-ip / --flannel-iface=eth0 are injected
    # automatically using the node's public IP, so YC nodes behave the
    # same as single-IP VPS nodes (timeweb/hostvds) at the k8s layer.
    k3s_install = optional(object({
      labels     = optional(list(string), [])
      taints     = optional(list(string), [])
      extra_args = optional(list(string), [])
    }), null)
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
