# yandex-vpn-entry

Generic Yandex Cloud VPN-node module. Each node entry has a `mode`:

- `adopt` — reuses an existing `yandex_compute_instance` + `yandex_vpc_address` + `yandex_vpc_security_group`
  by ID. The module reads live attributes through data sources, mirrors them into managed
  resources, and adds Terraform ownership labels + a guaranteed SSH/HTTPS ingress rules.
  Pairs with `lifecycle { prevent_destroy = true }` to make accidental destroy impossible.
- `create` — provisions a fresh VM + reserved public IP + security group from the given spec.
  `user_data` is where the VPN bootstrap one-liner (from `vpn-control-api` installer) belongs.

The role that a node plays in the VPN mesh (`backend`, `whitelist_entry`, etc.) is **not**
owned by Terraform. It is stored in `vpn-control-api` and injected at bootstrap time through
cloud-init / the installer script. Terraform only manages the cloud infrastructure.

## Adopting an existing node

```bash
cd terraform/yandex-vpn
terraform init -backend-config=../backends/yandex-vpn.hcl

# Terraform imports (run once per node):
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

`plan` must show **no changes** after import. If it does, either the catalog entry does not
match the live configuration or the module needs to learn another attribute; adjust the
catalog or module until `plan` is clean before applying.

## Inputs

Module variable schema (per node):

| Field                 | Required for                    | Notes                                              |
| --------------------- | ------------------------------- | -------------------------------------------------- |
| `mode`                | both                            | `adopt` or `create`                                |
| `instance_id`         | adopt                           | Existing VM ID                                     |
| `address_id`          | adopt                           | Existing reserved IP ID                            |
| `security_group_id`   | adopt                           | Existing SG ID                                     |
| `zone`                | create                          | YC zone, e.g. `ru-central1-a`                      |
| `subnet_id`           | create                          | YC subnet ID                                       |
| `network_id`          | create                          | YC VPC network ID                                  |
| `image_id`            | create                          | Boot disk image ID                                 |
| `platform_id`         | create (default `standard-v3`)  |                                                    |
| `cores`, `memory`     | create (default `2`, `2` GB)    |                                                    |
| `disk_size`           | create (default `20` GB)        |                                                    |
| `nat_enabled`         | create (default `true`)         |                                                    |
| `ssh_public_key`      | create                          | Attached as `ubuntu:${key}` in metadata `ssh-keys` |
| `user_data`           | create                          | cloud-init; put the installer one-liner here       |
| `labels`              | both                            | Merged on top of Terraform-managed labels          |
| `metadata`            | both                            | Merged on top of Terraform-managed metadata        |
| `ssh_ingress_cidrs`   | both (default `0.0.0.0/0`)      | SG rule source                                     |
| `https_ingress_cidrs` | both (default `0.0.0.0/0`)      | SG rule source                                     |
| `prevent_destroy`     | both (default `true`)           | Drives `deletion_protection`; `adopt` is hard-coded to `true` at the lifecycle level |
