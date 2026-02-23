# Declarative VPN topology.
# This file is the source of truth for VPN nodes.
# Secrets are NOT stored here.

allow_empty_vpn_nodes = false

# 1) Manual nodes by public IP (optional fallback mode)
vpn_nodes = {}

# 2) Existing HostVDS node(s) by server_id
provider_api_enabled = true
hostvds_vpn_nodes = {
  "vpn-hostvds-main-01" = {
    server_id = "66d46d44-253d-4a17-977d-a274b3d71e25"
    channel   = "prod"
    ssh_user  = "root"
    ssh_port  = 22
    enabled   = true
    region    = "eu-north1b"
  }
}

# 3) HostVDS compute mode (create/destroy VPS via Terraform)
# Enable only when you are ready to provision through OpenStack.
hostvds_compute_enabled = false
hostvds_provisioned_vpn_nodes = {
  # "vpn-hostvds-main-02" = {
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
