variable "vpn_domain" {
  description = "Primary VPN domain used in xray template."
  type        = string
}

variable "vpn_ws_path" {
  description = "WS path used in xray template."
  type        = string
}

variable "vpn_xhttp_path" {
  description = "XHTTP path used in xray template."
  type        = string
}

variable "vpn_dev_domain" {
  description = "Optional dev VPN domain override for dev xray config."
  type        = string
  default     = ""
}

variable "vpn_dev_ws_path" {
  description = "Optional dev WS path override for dev xray config."
  type        = string
  default     = ""
}

variable "vpn_dev_xhttp_path" {
  description = "Optional dev XHTTP path override for dev xray config."
  type        = string
  default     = ""
}

variable "enable_vpn_dev_stack" {
  description = "Render dev xray docker config for vpn-dev stack."
  type        = bool
  default     = false
}
