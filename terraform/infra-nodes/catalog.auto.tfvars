# Declarative non-VPN infrastructure topology (manager/workers).
# This file is the source of truth for infra nodes.
# Secrets are NOT stored here.

# 1) Manual nodes by public IP (optional fallback mode)
infra_nodes = {}

# 2) Existing Timeweb servers by server_id (recommended current mode)
# Set provider_api_enabled=true after replacing server_id placeholders below.
provider_api_enabled = true
timeweb_infra_nodes = {
  "infra-manager-01" = {
    server_id   = "6183431"
    role        = "manager"
    kind        = "prod"
    ssh_user    = "root"
    ssh_port    = 22
    ssh_key_ref = "default"
    enabled     = true
    region      = "ru-1"
  }
  "infra-worker-01" = {
    server_id   = "2669415"
    role        = "worker"
    kind        = "prod"
    ssh_user    = "root"
    ssh_port    = 22
    ssh_key_ref = "default"
    enabled     = true
    region      = "ru-1"
  }
}

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
    ssh_key_ref       = "default"
    enabled           = true
    region            = "spb-3"
  }
}
