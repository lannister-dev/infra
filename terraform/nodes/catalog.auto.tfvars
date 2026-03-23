# Declarative VPN topology.
# This file is the source of truth for VPN nodes.
# Secrets are NOT stored here.

allow_empty_vpn_nodes = false

# 1) Manual nodes by public IP (optional fallback mode)
vpn_nodes = {}

# 2) Existing provider node(s) by server_id (recommended mode for frequent provider rotation)
provider_api_vpn_nodes = {}

# Optional legacy switch (keep false; auto-enabled when provider_api_vpn_nodes has entries).
provider_api_enabled = false

# 3) Provider compute mode (create/destroy VPS via Terraform)
# Use this mode when you want full declarative node lifecycle.
provider_compute_vpn_nodes = {
  "vpn-hostvds-main-01" = {
    provider          = "hostvds"
    image_id          = "c54a6fb6-1bc6-490b-a5cd-9559232c9a3f"
    flavor_id         = "c356a6fe-ebff-4c44-aa1f-ada1d93023cc"
    network_ids       = ["b96e50cb-0d46-45a7-88f3-018158a1aa82"]
    key_pair          = "dev"
    availability_zone = "nova"
    security_groups   = ["allow_all"]
    channel           = "prod"
    ssh_user          = "root"
    ssh_port          = 22
    ssh_key_ref       = "dev"
    enabled           = true
    region            = "eu-west2"
    platform_region   = "fr"
  }

  "vpn-hostvds-main-02" = {
    provider        = "hostvds"
    image_id        = "62d4af7a-3afa-429b-b5a2-f7024a182080"
    flavor_id       = "9f0f82ef-1a2f-46ab-b1cf-f841246a9a8b"
    network_ids     = ["b447fbc8-155b-436b-b633-549c7e4951e8"]
    key_pair        = "dev"
    security_groups = ["allow_all"]
    channel         = "prod"
    ssh_user        = "root"
    ssh_port        = 22
    ssh_key_ref     = "dev"
    enabled         = true
    region          = "eu-north1b"
    platform_region = "fi" # eu-north1b → Finland
  }
}

# 4) Existing Yandex Cloud whitelist entry nodes (import/adoption mode, no recreate).
# These are first-hop VPN entry nodes and must keep their current VM + public IP.
yandex_whitelist_entry_nodes = {
 "vpn-yc-whitelist-entry-01" = {
      instance_id         = "fv49f95hm100jq8vgk23"
      address_id          = "fl86b7623dahu02oij23"
      security_group_id   = "enplegc9n5jud1sict6j"
      channel             = "prod"
      ssh_user            = "lannister"
      ssh_port            = 22
      ssh_key_ref         = "yc"
      enabled             = true
      region              = "ru-central1-d"
      platform_region     = "ru"
      ssh_ingress_cidrs   = ["0.0.0.0/0"]
      https_ingress_cidrs = ["0.0.0.0/0"]
      prevent_destroy     = true
    }
}

# Optional legacy switch/legacy map for backward compatibility.
hostvds_compute_enabled       = false
hostvds_vpn_nodes             = {}
hostvds_provisioned_vpn_nodes = {}
