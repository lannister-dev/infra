variable "nodes" {
  description = "Existing Yandex Cloud whitelist entry nodes to adopt into Terraform."
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
}
