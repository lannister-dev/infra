variable "nodes" {
  description = "HostVDS VPN nodes to provision via OpenStack."
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
}
