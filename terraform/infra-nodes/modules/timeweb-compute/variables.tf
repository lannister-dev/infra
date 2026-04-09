variable "nodes" {
  description = "Timeweb infra nodes to provision."
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
}
