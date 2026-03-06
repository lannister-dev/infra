# Declarative VPN topology for development environment.

# Allow empty set during initial bootstrap; set to false after first dev nodes are provisioned.
allow_empty_vpn_nodes = true

# 1) Manual nodes by public IP (optional fallback mode)
vpn_nodes = {}

# 2) Existing provider node(s) by server_id (recommended mode for provider rotation)
provider_api_vpn_nodes = {}

# 3) Provider compute mode (create/destroy VPS via Terraform)
provider_compute_vpn_nodes = {}

# Legacy compatibility maps (keep empty for new setup).
hostvds_compute_enabled       = false
hostvds_vpn_nodes             = {}
hostvds_provisioned_vpn_nodes = {}
