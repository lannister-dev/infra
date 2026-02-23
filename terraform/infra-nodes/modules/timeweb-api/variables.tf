variable "enabled" {
  description = "Enable Timeweb API lookup."
  type        = bool
  default     = false
}

variable "api_url" {
  description = "Timeweb API base URL."
  type        = string
}

variable "api_token" {
  description = "Timeweb API token."
  type        = string
  sensitive   = true
}

variable "auth_header" {
  description = "Auth header name."
  type        = string
  default     = "Authorization"
}

variable "auth_scheme" {
  description = "Auth scheme prefix."
  type        = string
  default     = "Bearer"
}

variable "endpoint_template" {
  description = "Endpoint template with {server_id} placeholder."
  type        = string
  default     = "/servers/{server_id}"
}

variable "nodes" {
  description = "Infra nodes keyed by node name."
  type = map(object({
    server_id = string
    role      = optional(string, "worker")
    kind      = optional(string, "prod")
    ssh_user  = optional(string, "root")
    ssh_port  = optional(number, 22)
    enabled   = optional(bool, true)
    region    = optional(string, "")
  }))
  default = {}
}
