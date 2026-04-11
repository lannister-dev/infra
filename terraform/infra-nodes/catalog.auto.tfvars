# 1) Manual nodes by public IP (optional fallback mode)
infra_nodes = {}

# 2) Existing Timeweb servers by server_id (legacy lookup mode)
provider_api_enabled = false
timeweb_infra_nodes  = {}

# 3) Timeweb compute mode (create/destroy VPS via Terraform)
timeweb_compute_enabled = true
timeweb_provisioned_infra_nodes = {
  "infra-manager-02" = {
    os_id             = 79
    location          = "ru-1"
    availability_zone = "spb-3"
    preset_type       = "premium"
    cpu               = 2
    ram               = 4096
    disk              = 40960
    ssh_keys_ids      = [314183]
    role              = "manager"
    kind              = "prod"
    ssh_user          = "root"
    ssh_port          = 22
    ssh_key_ref       = "prod_infra"
    enabled           = true
    region            = "spb-3"
  }
}
