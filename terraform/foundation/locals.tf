locals {
  root_dir = "${path.module}/../.."

  # Raw file content (used for both hashing and docker_config data)
  prometheus_config_data          = filebase64("${local.root_dir}/monitoring/prometheus/prometheus.yml")
  grafana_ini_config_data         = filebase64("${local.root_dir}/monitoring/grafana/grafana.ini")
  grafana_datasources_config_data = filebase64("${local.root_dir}/monitoring/grafana/provisioning/datasources/prometheus.yml")
  grafana_dashboards_config_data  = filebase64("${local.root_dir}/monitoring/grafana/provisioning/dashboards/dashboards.yml")
  vpn_fallback_index_data         = filebase64("${local.root_dir}/vpn/nginx/index.html")
  vpn_fallback_nginx_data         = filebase64("${local.root_dir}/vpn/nginx/server.conf")
  alertmanager_config_data        = filebase64("${local.root_dir}/monitoring/alertmanager/alertmanager.yml")
  prometheus_alert_rules_data     = filebase64("${local.root_dir}/monitoring/prometheus/rules/alerts.yml")
  vault_config_data               = filebase64("${local.root_dir}/vault/config.hcl")

  vpn_domain                  = trimspace(var.vpn_domain)
  vpn_ws_path                 = trimspace(var.vpn_ws_path)
  vpn_xhttp_path              = trimspace(var.vpn_xhttp_path)
  vpn_reality_dest_host       = trimspace(var.vpn_reality_dest_host)
  vpn_reality_server_name     = trimspace(var.vpn_reality_server_name)
  vpn_reality_private_key     = trimspace(var.vpn_reality_private_key)
  vpn_reality_short_id        = trimspace(var.vpn_reality_short_id)
  vpn_dev_domain              = trimspace(var.vpn_dev_domain)
  vpn_dev_ws_path             = trimspace(var.vpn_dev_ws_path)
  vpn_dev_xhttp_path          = trimspace(var.vpn_dev_xhttp_path)
  vpn_dev_reality_dest_host   = trimspace(var.vpn_dev_reality_dest_host)
  vpn_dev_reality_server_name = trimspace(var.vpn_dev_reality_server_name)
  vpn_dev_reality_private_key = trimspace(var.vpn_dev_reality_private_key)
  vpn_dev_reality_short_id    = trimspace(var.vpn_dev_reality_short_id)

  # Keep the dev config managed even when the vpn-dev stack is disabled.
  # When explicit dev values are absent, fall back to prod values.
  effective_vpn_dev_domain              = local.vpn_dev_domain != "" ? local.vpn_dev_domain : local.vpn_domain
  effective_vpn_dev_ws_path             = local.vpn_dev_ws_path != "" ? local.vpn_dev_ws_path : local.vpn_ws_path
  effective_vpn_dev_xhttp_path          = local.vpn_dev_xhttp_path != "" ? local.vpn_dev_xhttp_path : local.vpn_xhttp_path
  effective_vpn_dev_reality_dest_host   = local.vpn_dev_reality_dest_host != "" ? local.vpn_dev_reality_dest_host : local.vpn_reality_dest_host
  effective_vpn_dev_reality_server_name = local.vpn_dev_reality_server_name != "" ? local.vpn_dev_reality_server_name : local.vpn_reality_server_name
  effective_vpn_dev_reality_private_key = local.vpn_dev_reality_private_key != "" ? local.vpn_dev_reality_private_key : local.vpn_reality_private_key
  effective_vpn_dev_reality_short_id    = local.vpn_dev_reality_short_id != "" ? local.vpn_dev_reality_short_id : local.vpn_reality_short_id

  xray_config_rendered = templatefile("${local.root_dir}/vpn/xray/config.json.j2", {
    XRAY_LOG_LEVEL          = "info"
    VPN_DOMAIN              = local.vpn_domain
    VPN_WS_PATH             = local.vpn_ws_path
    VPN_XHTTP_PATH          = local.vpn_xhttp_path
    VPN_REALITY_SERVER_NAME = local.vpn_reality_server_name
    VPN_REALITY_PRIVATE_KEY = local.vpn_reality_private_key
    VPN_REALITY_SHORT_ID    = local.vpn_reality_short_id
    VPN_REALITY_DEST_HOST   = local.vpn_reality_dest_host
    VPN_REALITY_DEST_DOMAIN = "full:${local.vpn_reality_dest_host}"
  })

  xray_config_dev_rendered = templatefile("${local.root_dir}/vpn/xray/config.json.j2", {
    XRAY_LOG_LEVEL          = "info"
    VPN_DOMAIN              = local.effective_vpn_dev_domain
    VPN_WS_PATH             = local.effective_vpn_dev_ws_path
    VPN_XHTTP_PATH          = local.effective_vpn_dev_xhttp_path
    VPN_REALITY_SERVER_NAME = local.effective_vpn_dev_reality_server_name
    VPN_REALITY_PRIVATE_KEY = local.effective_vpn_dev_reality_private_key
    VPN_REALITY_SHORT_ID    = local.effective_vpn_dev_reality_short_id
    VPN_REALITY_DEST_HOST   = local.effective_vpn_dev_reality_dest_host
    VPN_REALITY_DEST_DOMAIN = "full:${local.effective_vpn_dev_reality_dest_host}"
  })

  xray_config_data     = base64encode(local.xray_config_rendered)
  xray_config_dev_data = base64encode(local.xray_config_dev_rendered)

  # Content-hash based config names: auto-rotate on any file change
  prometheus_config_name             = "prometheus_config__${substr(sha256(local.prometheus_config_data), 0, 8)}"
  grafana_ini_config_name            = "grafana_ini__${substr(sha256(local.grafana_ini_config_data), 0, 8)}"
  grafana_datasources_config_name    = "grafana_datasources__${substr(sha256(local.grafana_datasources_config_data), 0, 8)}"
  grafana_dashboards_config_name     = "grafana_dashboards__${substr(sha256(local.grafana_dashboards_config_data), 0, 8)}"
  xray_config_name                   = "xray_config__${substr(sha256(local.xray_config_data), 0, 8)}"
  xray_config_dev_name               = "xray_config_dev__${substr(sha256(local.xray_config_dev_data), 0, 8)}"
  vpn_fallback_index_config_name     = "vpn_fallback_index__${substr(sha256(local.vpn_fallback_index_data), 0, 8)}"
  vpn_fallback_nginx_config_name     = "vpn_fallback_nginx_conf__${substr(sha256(local.vpn_fallback_nginx_data), 0, 8)}"
  alertmanager_config_name           = "alertmanager_config__${substr(sha256(local.alertmanager_config_data), 0, 8)}"
  prometheus_alert_rules_config_name = "prometheus_alert_rules__${substr(sha256(local.prometheus_alert_rules_data), 0, 8)}"
  vault_config_name                  = "vault_conf__${substr(sha256(local.vault_config_data), 0, 8)}"
}

check "vpn_dev_explicit_values" {
  assert {
    condition = !var.enable_vpn_dev_stack || alltrue([
      trimspace(var.vpn_dev_domain) != "",
      trimspace(var.vpn_dev_ws_path) != "",
      trimspace(var.vpn_dev_xhttp_path) != "",
      trimspace(var.vpn_dev_reality_server_name) != "",
      trimspace(var.vpn_dev_reality_private_key) != "",
      trimspace(var.vpn_dev_reality_private_key) != "<x25519_private_key>",
      trimspace(var.vpn_dev_reality_short_id) != "",
      trimspace(var.vpn_dev_reality_short_id) != "<short_id_hex>",
      trimspace(var.vpn_dev_reality_dest_host) != "",
    ])
    error_message = "When enable_vpn_dev_stack=true, set all vpn_dev_* fields explicitly with real values."
  }
}
