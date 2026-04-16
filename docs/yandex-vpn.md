# Yandex Cloud VPN Nodes

Yandex Cloud is the one VPN provider where Terraform still owns the compute layer.
Every non-YC VPN node is provisioned through `vpn-control-api` (admin UI → installer
one-liner), not Terraform.

Root: `terraform/yandex-vpn/`
Backend: `terraform/backends/yandex-vpn.hcl.example`
Module: `terraform/yandex-vpn/modules/yandex-vpn-entry/`

## Modes

Each entry in `yandex_vpn_nodes` selects a mode:

- `adopt` — existing `yandex_compute_instance` + `yandex_vpc_address`
  + `yandex_vpc_security_group` are taken over by ID. The module reads live attributes
  through data sources, mirrors them into managed resources, adds Terraform ownership
  labels, and guarantees SSH/HTTPS ingress rules. `prevent_destroy = true` is enforced at
  the lifecycle level.
- `create` — fresh VM + reserved public IP + security group from the given spec. Put the
  control-api installer one-liner into `user_data`.

The VPN traffic role (`backend`, `whitelist_entry`, …) lives in `vpn-control-api` and is
injected at bootstrap via cloud-init; Terraform does not own it.

## Initial adoption of the legacy whitelist-entry node

Legacy VPN provisioning (`terraform/nodes`) was removed in favour of this root. The only
node that needed to move into the new state was the YC whitelist-entry node. Either
`terraform state mv` between state files, or — preferred — `terraform state rm` in the old
state followed by `terraform import` in the new one:

```bash
cd terraform/yandex-vpn
terraform init -backend-config=../backends/yandex-vpn.hcl

terraform import \
  'module.yandex_vpn_entry[0].yandex_compute_instance.adopted["vpn-yc-whitelist-entry-01"]' \
  fv49f95hm100jq8vgk23

terraform import \
  'module.yandex_vpn_entry[0].yandex_vpc_address.adopted["vpn-yc-whitelist-entry-01"]' \
  fl86b7623dahu02oij23

terraform import \
  'module.yandex_vpn_entry[0].yandex_vpc_security_group.adopted["vpn-yc-whitelist-entry-01"]' \
  enplegc9n5jud1sict6j

terraform plan
```

`plan` must show no changes. If it does not, fix the catalog or the module before applying.

After the cut-over, the orphan `prod/nodes.tfstate` key can be removed from the S3 state
bucket by the operator.

## Creating new YC VPN nodes

```hcl
yandex_vpn_nodes = {
  "vpn-yc-backend-01" = {
    mode            = "create"
    zone            = "ru-central1-b"
    subnet_id       = "e2l***************"
    network_id      = "enp***************"
    image_id        = "fd8***************"
    platform_id     = "standard-v3"
    cores           = 2
    memory          = 2
    disk_size       = 20
    nat_enabled     = true
    ssh_public_key  = "ssh-ed25519 AAAA... admin"
    user_data       = "#!/bin/bash\ncurl -fsSL https://control.example.com/agent/install.sh | TOKEN=... bash\n"
    prevent_destroy = false
  }
}
```

Apply with:

```bash
cd terraform/yandex-vpn
terraform init -backend-config=../backends/yandex-vpn.hcl
terraform plan
terraform apply
```

## Credentials

Prefer `yandex_service_account_key_file` (or `YC_SERVICE_ACCOUNT_KEY_B64` in CI) over
`YC_TOKEN`; short-lived IAM tokens expire mid-run.
