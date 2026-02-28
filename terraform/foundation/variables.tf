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

variable "vpn_reality_server_name" {
  description = "REALITY serverName used in xray template."
  type        = string
  default     = ""
}

variable "vpn_reality_private_key" {
  description = "REALITY private key for xray template."
  type        = string
  default     = "M4cZLR81ErNfxnG1fAnNUIATs_UXqe6HR78wINhH7RA"
}

variable "vpn_reality_short_id" {
  description = "REALITY shortId used in xray template."
  type        = string
  default     = "6ba85179e30d4fc2"
}

variable "vpn_reality_dest_host" {
  description = "REALITY fallback destination host for anti-steal routing."
  type        = string
  default     = "www.cloudflare.com"
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

variable "vpn_dev_reality_server_name" {
  description = "Optional dev REALITY serverName override for dev xray config."
  type        = string
  default     = ""
}

variable "vpn_dev_reality_private_key" {
  description = "Optional dev REALITY private key override for dev xray config."
  type        = string
  default     = ""
}

variable "vpn_dev_reality_short_id" {
  description = "Optional dev REALITY shortId override for dev xray config."
  type        = string
  default     = ""
}

variable "vpn_dev_reality_dest_host" {
  description = "Optional dev REALITY fallback destination host override."
  type        = string
  default     = ""
}

variable "enable_vpn_dev_stack" {
  description = "Render dev xray docker config for vpn-dev stack."
  type        = bool
  default     = false
}
