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

    labels              = optional(map(string), {})
    metadata            = optional(map(string), {})
    ssh_ingress_cidrs           = optional(list(string), ["0.0.0.0/0"])
    https_ingress_cidrs         = optional(list(string), ["0.0.0.0/0"])
    kubelet_ingress_cidrs       = optional(list(string), [])
    node_exporter_ingress_cidrs = optional(list(string), [])
    prevent_destroy             = optional(bool, true)
  }))
  default = {}
}
