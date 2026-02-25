# Declarative VPN topology.
# This file is the source of truth for VPN nodes.
# Secrets are NOT stored here.

allow_empty_vpn_nodes = false

# 1) Manual nodes by public IP (optional fallback mode)
vpn_nodes = {}

# 2) Existing provider node(s) by server_id (recommended mode for frequent provider rotation)
provider_api_vpn_nodes = {
  "vpn-hostvds-main-01" = {
    provider  = "hostvds"
    server_id = "66d46d44-253d-4a17-977d-a274b3d71e25"
    channel   = "prod"
    ssh_user  = "root"
    ssh_port  = 22
    enabled   = true
    region    = "eu-north1b"
  },
  "vpn-hostvds-main-02" = {
    provider  = "hostvds"
    server_id = "d72258aa-36f8-4193-9e2c-dbb311e13439"
    channel   = "prod"
    ssh_user  = "root"
    ssh_port  = 22
    enabled   = true
    region    = "eu-west2"
  }
}

# Optional legacy switch (keep false; auto-enabled when provider_api_vpn_nodes has entries).
provider_api_enabled = false

# 3) Provider compute mode (create/destroy VPS via Terraform)
# Use this mode when you want full declarative node lifecycle.
provider_compute_vpn_nodes = {
  # "vpn-hostvds-main-02" = {
  #   provider    = "hostvds"
  #   image_id    = "REPLACE_IMAGE_ID"
  #   flavor_id   = "REPLACE_FLAVOR_ID"
  #   network_ids = ["REPLACE_NETWORK_ID"]
  #   key_pair    = "main-key"
  #   channel     = "prod"
  #   ssh_user    = "root"
  #   ssh_port    = 22
  #   enabled     = true
  #   region      = "eu-west2"
  # }
}

# Optional legacy switch/legacy map for backward compatibility.
hostvds_compute_enabled       = false
hostvds_vpn_nodes             = {}
hostvds_provisioned_vpn_nodes = {}
