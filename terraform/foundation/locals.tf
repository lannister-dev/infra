locals {
  root_dir = "${path.module}/../.."

  prometheus_config_name          = "prometheus_config__${var.prometheus_config_version}"
  grafana_ini_config_name         = "grafana_ini__${var.grafana_ini_version}"
  grafana_datasources_config_name = "grafana_datasources__${var.grafana_datasources_version}"
  grafana_dashboards_config_name  = "grafana_dashboards__${var.grafana_dashboards_version}"
  xray_config_name                = "xray_config__${var.xray_config_version}"
  xray_config_dev_name            = "xray_config_dev__${var.xray_config_dev_version}"
  vpn_fallback_index_config_name  = "vpn_fallback_index__${var.vpn_fallback_index_version}"
  vpn_fallback_nginx_config_name  = "vpn_fallback_nginx_conf__${var.vpn_fallback_nginx_config_version}"

  vpn_dev_domain     = trimspace(var.vpn_dev_domain) != "" ? var.vpn_dev_domain : var.vpn_domain
  vpn_dev_ws_path    = trimspace(var.vpn_dev_ws_path) != "" ? var.vpn_dev_ws_path : var.vpn_ws_path
  vpn_dev_xhttp_path = trimspace(var.vpn_dev_xhttp_path) != "" ? var.vpn_dev_xhttp_path : var.vpn_xhttp_path

  xray_config_rendered = templatefile("${local.root_dir}/vpn/xray/config.json.j2", {
    VPN_DOMAIN     = var.vpn_domain
    VPN_WS_PATH    = var.vpn_ws_path
    VPN_XHTTP_PATH = var.vpn_xhttp_path
  })

  xray_config_dev_rendered = templatefile("${local.root_dir}/vpn/xray/config.json.j2", {
    VPN_DOMAIN     = local.vpn_dev_domain
    VPN_WS_PATH    = local.vpn_dev_ws_path
    VPN_XHTTP_PATH = local.vpn_dev_xhttp_path
  })
}
