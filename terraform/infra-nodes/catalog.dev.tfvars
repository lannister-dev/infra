# Declarative non-VPN infrastructure topology for development environment.

# 1) Manual nodes by public IP (optional fallback mode)
infra_nodes = {}

# 2) Existing Timeweb servers by server_id.
provider_api_enabled = true
timeweb_infra_nodes = {
  "infra-worker-01" = {
    server_id   = "2669415"
    role        = "worker"
    kind        = "dev"
    ssh_user    = "root"
    ssh_port    = 22
    ssh_key_ref = "prod_infra"
    enabled     = true
    region      = "ru-1"
  }
}

# 3) Timeweb compute mode (create/destroy VPS via Terraform)
timeweb_compute_enabled         = false
timeweb_provisioned_infra_nodes = {}
