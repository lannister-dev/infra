resource "docker_network" "traefik_swarm" {
  name       = "traefik_swarm"
  driver     = "overlay"
  attachable = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_network" "monitoring" {
  name       = "monitoring"
  driver     = "overlay"
  attachable = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_network" "vpn_net" {
  name       = "vpn-net"
  driver     = "overlay"
  attachable = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_volume" "traefik_acme" {
  name = "traefik_acme"

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_volume" "prometheus_data" {
  name = "prometheus_data"

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_volume" "grafana_data" {
  name = "grafana_data"

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_volume" "agent_data" {
  name = "agent-data"

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_config" "prometheus_config" {
  name = local.prometheus_config_name
  data = filebase64("${local.root_dir}/monitoring/prometheus/prometheus.yml")
}

resource "docker_config" "grafana_ini_config" {
  name = local.grafana_ini_config_name
  data = filebase64("${local.root_dir}/monitoring/grafana/grafana.ini")
}

resource "docker_config" "grafana_datasources_config" {
  name = local.grafana_datasources_config_name
  data = filebase64("${local.root_dir}/monitoring/grafana/provisioning/datasources/prometheus.yml")
}

resource "docker_config" "grafana_dashboards_config" {
  name = local.grafana_dashboards_config_name
  data = filebase64("${local.root_dir}/monitoring/grafana/provisioning/dashboards/dashboards.yml")
}

resource "docker_config" "xray_config" {
  name = local.xray_config_name
  data = base64encode(local.xray_config_rendered)
}

resource "docker_config" "xray_config_dev" {
  count = var.enable_vpn_dev_stack ? 1 : 0
  name  = local.xray_config_dev_name
  data  = base64encode(local.xray_config_dev_rendered)
}

resource "docker_config" "vpn_fallback_index" {
  name = local.vpn_fallback_index_config_name
  data = filebase64("${local.root_dir}/vpn/nginx/index.html")
}

resource "docker_config" "vpn_fallback_nginx_conf" {
  name = local.vpn_fallback_nginx_config_name
  data = filebase64("${local.root_dir}/vpn/nginx/server.conf")
}
