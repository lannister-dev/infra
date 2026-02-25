variable "nodes" {
  description = "HostVDS VPN nodes to provision via OpenStack."
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
    enabled           = optional(bool, true)
    region            = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, node in var.nodes : (
        (length(trimspace(node.image_id)) > 0 || length(trimspace(node.image_name)) > 0)
        && (length(trimspace(node.flavor_id)) > 0 || length(trimspace(node.flavor_name)) > 0)
      )
    ])
    error_message = "Each node must define image_id or image_name, and flavor_id or flavor_name."
  }
}
