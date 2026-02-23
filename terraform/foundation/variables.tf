variable "prometheus_config_version" {
  description = "Version suffix for Prometheus swarm config."
  type        = string
  default     = "V1_4"
}

variable "grafana_ini_version" {
  description = "Version suffix for Grafana ini swarm config."
  type        = string
  default     = "V1_0"
}

variable "grafana_datasources_version" {
  description = "Version suffix for Grafana datasource swarm config."
  type        = string
  default     = "V1_1"
}

variable "grafana_dashboards_version" {
  description = "Version suffix for Grafana dashboard provisioning config."
  type        = string
  default     = "V1_0"
}

variable "xray_config_version" {
  description = "Version suffix for prod xray swarm config."
  type        = string
  default     = "V3_2"
}

variable "xray_config_dev_version" {
  description = "Version suffix for dev xray swarm config."
  type        = string
  default     = "V2_9"
}

variable "vpn_fallback_index_version" {
  description = "Version suffix for fallback index config."
  type        = string
  default     = "V1_1"
}

variable "vpn_fallback_nginx_config_version" {
  description = "Version suffix for fallback nginx config."
  type        = string
  default     = "V1_1"
}

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
