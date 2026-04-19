# Declarative Yandex Cloud VPN-node topology.
# This file is the source of truth for YC-hosted VPN nodes only.
# Secrets are NOT stored here — the k3s join token is read from Vault.
#
# Non-YC VPN nodes are managed through vpn-control-api (admin UI +
# installer bootstrap script). Terraform does not own them.

# SSH used by netplan/k3s on-VM provisioners. `yc compute ssh` requires
# the IAM username to exist on the VM; for hand-curated images it
# doesn't, so we use plain SSH with a dedicated key instead.
ssh_identity_file = "~/.ssh/id_ed25519_yandex"
ssh_user          = "lannister"

yandex_vpn_nodes = {
  "vpn-yc-whitelist-entry-01" = {
    mode                        = "adopt"
    instance_id                 = "fv49f95hm100jq8vgk23"
    address_id                  = "fl8ipg4jkbf9avddt9sb"
    security_group_id           = "enplegc9n5jud1sict6j"
    zone                        = "ru-central1-d"
    ssh_ingress_cidrs           = ["0.0.0.0/0"]
    https_ingress_cidrs         = ["0.0.0.0/0"]
    kubelet_ingress_cidrs       = ["82.97.253.81/32"]
    node_exporter_ingress_cidrs = ["82.97.253.81/32"]
    prevent_destroy             = true

    k3s_install = {
      labels = [
        "role=vpn",
        "channel=prod",
        "provider=yandex-cloud",
        "traffic_role=whitelist_entry",
      ]
      taints     = ["dedicated=vpn:NoSchedule"]
      extra_args = []
    }
  }
}
