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
  data = local.prometheus_config_data
}

resource "docker_config" "grafana_ini_config" {
  name = local.grafana_ini_config_name
  data = local.grafana_ini_config_data
}

resource "docker_config" "grafana_datasources_config" {
  name = local.grafana_datasources_config_name
  data = local.grafana_datasources_config_data
}

resource "docker_config" "grafana_dashboards_config" {
  name = local.grafana_dashboards_config_name
  data = local.grafana_dashboards_config_data
}

resource "docker_config" "xray_config" {
  name = local.xray_config_name
  data = local.xray_config_data
}

resource "docker_config" "xray_config_dev" {
  name = local.xray_config_dev_name
  data = local.xray_config_dev_data
}

resource "docker_config" "vpn_fallback_index" {
  name = local.vpn_fallback_index_config_name
  data = local.vpn_fallback_index_data
}

resource "docker_config" "vpn_fallback_nginx_conf" {
  name = local.vpn_fallback_nginx_config_name
  data = local.vpn_fallback_nginx_data
}
