output "docker_config_names" {
  description = "Resolved docker config names managed by Terraform foundation."
  value = {
    prometheus          = local.prometheus_config_name
    grafana_ini         = local.grafana_ini_config_name
    grafana_datasources = local.grafana_datasources_config_name
    grafana_dashboards  = local.grafana_dashboards_config_name
    xray                = local.xray_config_name
    xray_dev            = local.xray_config_dev_name
    vpn_fallback_index  = local.vpn_fallback_index_config_name
    vpn_fallback_nginx  = local.vpn_fallback_nginx_config_name
    vault               = local.vault_config_name
  }
}

output "network_names" {
  description = "Swarm overlay networks created by Terraform foundation."
  value = {
    traefik    = docker_network.traefik_swarm.name
    monitoring = docker_network.monitoring.name
    vpn        = docker_network.vpn_net.name
  }
}

output "volume_names" {
  description = "Persistent volumes created by Terraform foundation."
  value = {
    traefik_acme    = docker_volume.traefik_acme.name
    prometheus_data = docker_volume.prometheus_data.name
    grafana_data    = docker_volume.grafana_data.name
    agent_data      = docker_volume.agent_data.name
  }
}
