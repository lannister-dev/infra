variable "enabled" {
  description = "Enable HostVDS API lookup."
  type        = bool
  default     = false
}

variable "os_auth_url" {
  description = "OpenStack Keystone auth URL (OS_AUTH_URL)."
  type        = string
}

variable "os_username" {
  description = "OpenStack username (OS_USERNAME)."
  type        = string
}

variable "os_password" {
  description = "OpenStack password (OS_PASSWORD)."
  type        = string
  sensitive   = true
}

variable "os_project_name" {
  description = "OpenStack project name (OS_PROJECT_NAME)."
  type        = string
}

variable "os_user_domain_name" {
  description = "OpenStack user domain name (OS_USER_DOMAIN_NAME)."
  type        = string
  default     = ""
}

variable "os_user_domain_id" {
  description = "OpenStack user domain id (OS_USER_DOMAIN_ID). Optional alternative to name."
  type        = string
  default     = ""
}

variable "os_project_domain_name" {
  description = "OpenStack project domain name (OS_PROJECT_DOMAIN_NAME)."
  type        = string
  default     = ""
}

variable "os_project_domain_id" {
  description = "OpenStack project domain id (OS_PROJECT_DOMAIN_ID). Optional alternative to name."
  type        = string
  default     = ""
}

variable "os_region_name" {
  description = "OpenStack region name (OS_REGION_NAME). Empty means first matching endpoint."
  type        = string
  default     = ""
}

variable "os_interface" {
  description = "OpenStack interface type for endpoint discovery (public/internal/admin)."
  type        = string
  default     = ""
}

variable "nodes" {
  description = "VPN nodes keyed by peer name."
  type = map(object({
    server_id   = string
    channel     = optional(string, "prod")
    ssh_user    = optional(string, "root")
    ssh_port    = optional(number, 22)
    ssh_key_ref = optional(string, "default")
    enabled     = optional(bool, true)
    region          = optional(string, "")
    platform_region = optional(string, "")
  }))
  default = {}
}
