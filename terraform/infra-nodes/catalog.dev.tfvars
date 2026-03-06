# Declarative non-VPN infrastructure topology for development environment.

# 1) Manual nodes by public IP (optional fallback mode)
infra_nodes = {}

# 2) Existing Timeweb servers by server_id.
provider_api_enabled = false
timeweb_infra_nodes  = {}

# 3) Timeweb compute mode (create/destroy VPS via Terraform)
timeweb_compute_enabled            = false
timeweb_provisioned_infra_nodes    = {}
