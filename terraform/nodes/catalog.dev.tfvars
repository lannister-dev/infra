# Declarative VPN topology for development environment.

# Safety guard: do not allow accidental full decommission from empty dev catalog.
allow_empty_vpn_nodes = false

# 1) Manual nodes by public IP (optional fallback mode)
vpn_nodes = {}

# 2) Existing provider node(s) by server_id (recommended mode for provider rotation)
provider_api_vpn_nodes = {}

# 3) Provider compute mode (create/destroy VPS via Terraform)
provider_compute_vpn_nodes = {}

# 4) Existing Yandex Cloud whitelist entry nodes (import/adoption mode)
yandex_whitelist_entry_nodes = {}

# Legacy compatibility maps (keep empty for new setup).
hostvds_compute_enabled       = false
hostvds_vpn_nodes             = {}
hostvds_provisioned_vpn_nodes = {}
