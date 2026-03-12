variable "vpn_domain" {
  description = "Primary VPN domain used in xray template."
  type        = string

  validation {
    condition     = trimspace(var.vpn_domain) != ""
    error_message = "vpn_domain must be set explicitly."
  }
}

variable "vpn_ws_path" {
  description = "WS path used in xray template."
  type        = string

  validation {
    condition     = trimspace(var.vpn_ws_path) != ""
    error_message = "vpn_ws_path must be set explicitly."
  }
}

variable "vpn_xhttp_path" {
  description = "XHTTP path used in xray template."
  type        = string

  validation {
    condition     = trimspace(var.vpn_xhttp_path) != ""
    error_message = "vpn_xhttp_path must be set explicitly."
  }
}

variable "vpn_reality_server_name" {
  description = "REALITY serverName used in xray template."
  type        = string

  validation {
    condition     = trimspace(var.vpn_reality_server_name) != ""
    error_message = "vpn_reality_server_name must be set explicitly."
  }
}

variable "vpn_reality_private_key" {
  description = "REALITY private key for xray template."
  type        = string

  validation {
    condition     = trimspace(var.vpn_reality_private_key) != "" && trimspace(var.vpn_reality_private_key) != "<x25519_private_key>"
    error_message = "vpn_reality_private_key must be set to a real X25519 private key."
  }
}

variable "vpn_reality_short_id" {
  description = "REALITY shortId used in xray template."
  type        = string

  validation {
    condition     = trimspace(var.vpn_reality_short_id) != "" && trimspace(var.vpn_reality_short_id) != "<short_id_hex>"
    error_message = "vpn_reality_short_id must be set to a real REALITY shortId."
  }
}

variable "vpn_reality_dest_host" {
  description = "REALITY fallback destination host for anti-steal routing."
  type        = string

  validation {
    condition     = trimspace(var.vpn_reality_dest_host) != ""
    error_message = "vpn_reality_dest_host must be set explicitly."
  }
}

variable "vpn_dev_domain" {
  description = "Dev VPN domain used in dev xray config when enable_vpn_dev_stack=true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_vpn_dev_stack || trimspace(var.vpn_dev_domain) != ""
    error_message = "vpn_dev_domain must be set when enable_vpn_dev_stack=true."
  }
}

variable "vpn_dev_ws_path" {
  description = "Dev WS path used in dev xray config when enable_vpn_dev_stack=true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_vpn_dev_stack || trimspace(var.vpn_dev_ws_path) != ""
    error_message = "vpn_dev_ws_path must be set when enable_vpn_dev_stack=true."
  }
}

variable "vpn_dev_xhttp_path" {
  description = "Dev XHTTP path used in dev xray config when enable_vpn_dev_stack=true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_vpn_dev_stack || trimspace(var.vpn_dev_xhttp_path) != ""
    error_message = "vpn_dev_xhttp_path must be set when enable_vpn_dev_stack=true."
  }
}

variable "vpn_dev_reality_server_name" {
  description = "Dev REALITY serverName used in dev xray config when enable_vpn_dev_stack=true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_vpn_dev_stack || trimspace(var.vpn_dev_reality_server_name) != ""
    error_message = "vpn_dev_reality_server_name must be set when enable_vpn_dev_stack=true."
  }
}

variable "vpn_dev_reality_private_key" {
  description = "Dev REALITY private key used in dev xray config when enable_vpn_dev_stack=true."
  type        = string
  default     = ""

  validation {
    condition = !var.enable_vpn_dev_stack || (
      trimspace(var.vpn_dev_reality_private_key) != "" &&
      trimspace(var.vpn_dev_reality_private_key) != "<x25519_private_key>"
    )
    error_message = "vpn_dev_reality_private_key must be set to a real X25519 private key when enable_vpn_dev_stack=true."
  }
}

variable "vpn_dev_reality_short_id" {
  description = "Dev REALITY shortId used in dev xray config when enable_vpn_dev_stack=true."
  type        = string
  default     = ""

  validation {
    condition = !var.enable_vpn_dev_stack || (
      trimspace(var.vpn_dev_reality_short_id) != "" &&
      trimspace(var.vpn_dev_reality_short_id) != "<short_id_hex>"
    )
    error_message = "vpn_dev_reality_short_id must be set to a real REALITY shortId when enable_vpn_dev_stack=true."
  }
}

variable "vpn_dev_reality_dest_host" {
  description = "Dev REALITY fallback destination host when enable_vpn_dev_stack=true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_vpn_dev_stack || trimspace(var.vpn_dev_reality_dest_host) != ""
    error_message = "vpn_dev_reality_dest_host must be set when enable_vpn_dev_stack=true."
  }
}

variable "enable_vpn_dev_stack" {
  description = "Render dev xray docker config for vpn-dev stack."
  type        = bool
}
