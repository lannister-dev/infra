variable "ssh_identity_file" {
  description = "Path to the private SSH key used by `yc compute ssh` for on-VM provisioners (ufw). If empty, yc CLI falls back to OS Login with an IAM-issued cert."
  type        = string
  default     = ""
}

variable "nodes" {
  description = "Yandex Cloud VPN nodes. mode=adopt adopts existing infra by IDs; mode=create provisions fresh resources."
  type = map(object({
    mode = string

    instance_id       = optional(string, "")
    address_id        = optional(string, "")
    security_group_id = optional(string, "")

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

    labels                      = optional(map(string), {})
    metadata                    = optional(map(string), {})
    ssh_ingress_cidrs           = optional(list(string), ["0.0.0.0/0"])
    https_ingress_cidrs         = optional(list(string), ["0.0.0.0/0"])
    kubelet_ingress_cidrs       = optional(list(string), [])
    node_exporter_ingress_cidrs = optional(list(string), [])
    prevent_destroy             = optional(bool, true)

    k3s_install = optional(object({
      labels     = optional(list(string), [])
      taints     = optional(list(string), [])
      extra_args = optional(list(string), [])
    }), null)
  }))
  default = {}
}

variable "k3s_join_url" {
  description = "K3s server URL (e.g. https://212.113.117.153:6443). Required when any node has k3s_install set."
  type        = string
  default     = ""
}

variable "k3s_join_token" {
  description = "K3s node-join token. Required when any node has k3s_install set."
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssh_user" {
  description = "SSH login used by netplan/k3s provisioners when `ssh_identity_file` is also set. Empty falls back to `yc compute ssh` (OS Login). YC default image ships `ubuntu`."
  type        = string
  default     = ""
}
