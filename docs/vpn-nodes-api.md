# VPN Nodes Catalog (Provider-Agnostic)

`terraform/nodes` supports three modes and keeps one normalized inventory output for Ansible.

## 1) Manual nodes (fallback)

Declare static nodes in `vpn_nodes`:

```hcl
vpn_nodes = {
  "vpn-nl-01" = {
    public_ip = "203.0.113.10"
    channel   = "prod"
    ssh_user  = "root"
    ssh_port  = 22
    enabled   = true
    provider  = "manual"
    region    = "eu-nl"
  }
}
```

## 2) Existing provider servers by `server_id` (recommended)

Declare nodes in `provider_api_vpn_nodes`:

```hcl
provider_api_vpn_nodes = {
  "vpn-hostvds-01" = {
    provider  = "hostvds"
    server_id = "66d46d44-253d-4a17-977d-a274b3d71e25"
    channel   = "prod"
    enabled   = true
    region    = "eu-west2"
  }
}
```

Terraform resolves `public_ip` through provider API module and writes normalized inventory.

## 3) Provider compute create/destroy (recommended for frequent node rotation)

Declare compute nodes in `provider_compute_vpn_nodes`:

```hcl
provider_compute_vpn_nodes = {
  "vpn-hostvds-02" = {
    provider    = "hostvds"
    image_name  = "Ubuntu-22.04-amd64"
    flavor_name = "hostvds-4"
    network_ids = ["76920584-3a19-4c67-bcc1-01407bedf558"]
    key_pair    = "main-key"
    channel     = "prod"
    enabled     = true
    region      = "eu-west2"
  }
}
```

`image_name`/`flavor_name` are preferred for cross-region stability; use IDs only when pinned.

Flow:
1. Terraform creates/replaces instance.
2. Terraform resolves `public_ip`.
3. Terraform writes normalized inventory.
4. Ansible reconciles WireGuard + Swarm.

## Credentials

For `provider=hostvds`:
- `HOSTVDS_OS_AUTH_URL`
- `HOSTVDS_OS_USERNAME`
- `HOSTVDS_OS_PASSWORD`
- `HOSTVDS_OS_PROJECT_NAME`
- `HOSTVDS_OS_USER_DOMAIN_NAME` or `HOSTVDS_OS_USER_DOMAIN_ID`
- `HOSTVDS_OS_PROJECT_DOMAIN_NAME` or `HOSTVDS_OS_PROJECT_DOMAIN_ID`
- `HOSTVDS_OS_REGION_NAME`
- `HOSTVDS_OS_INTERFACE`

## Lifecycle semantics

- `enabled = false`: node removed from desired cluster state, VM remains.
- Removing key from `provider_compute_vpn_nodes`: VM is destroyed.

## Provider rotation algorithm (ban/failure scenario)

1. Mark failed node as `enabled = false` (or remove key).
2. Add replacement entry in `provider_api_vpn_nodes` or `provider_compute_vpn_nodes`.
3. Run Terraform + reconcile playbook.
4. After drain/decommission confirmation, remove old entry completely.

## Legacy compatibility

`hostvds_vpn_nodes` and `hostvds_provisioned_vpn_nodes` are still supported for backward compatibility, but new changes should use `provider_*` catalogs.

## How to add a new provider

1. Implement provider module(s) in `terraform/nodes/modules/<provider>-api` and/or `terraform/nodes/modules/<provider>-compute`.
2. Extend dispatch/merge logic in `terraform/nodes/locals.tf` (`*_from_provider_catalog`).
3. Wire module calls in `terraform/nodes/main.tf`.
4. Add provider credentials to `.env` (local) and `INFRA_ENV_PROD` (CI secret).
5. Extend provider allowlist validations in `terraform/nodes/variables.tf`.
6. Keep Ansible unchanged: it consumes normalized `vpn_nodes` output.
