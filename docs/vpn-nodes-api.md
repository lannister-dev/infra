# VPN Nodes and Provider API

`terraform/nodes` supports three operational modes.

## 1) Manual nodes

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

## 2) Existing HostVDS servers (API lookup)

Declare server IDs in `hostvds_vpn_nodes` and enable API lookup:

```hcl
provider_api_enabled = true

hostvds_vpn_nodes = {
  "vpn-hv-01" = {
    server_id = "uuid-or-id"
    channel   = "prod"
    enabled   = true
    region    = "eu-west2"
  }
}
```

Terraform resolves `public_ip` via OpenStack API.

## 3) HostVDS compute create/destroy

Declare desired compute nodes in `hostvds_provisioned_vpn_nodes`:

```hcl
hostvds_compute_enabled = true

hostvds_provisioned_vpn_nodes = {
  "vpn-hv-02" = {
    image_id    = "2c6a2df7-8207-488d-abe9-77df29422ab1"
    flavor_id   = "3ce84631-91df-4ff2-bf59-d549909232dc"
    network_ids = ["76920584-3a19-4c67-bcc1-01407bedf558"]
    key_pair    = "main-key"
    channel     = "prod"
    enabled     = true
    region      = "eu-west2"
  }
}
```

Flow:
1. Terraform creates instance.
2. Terraform resolves instance public IP via OpenStack.
3. Terraform writes normalized inventory.
4. Ansible reconciles node into WireGuard + Swarm.

## Credentials and server IDs

Credentials are taken from `.env`/secret storage:
- `HOSTVDS_OS_AUTH_URL`
- `HOSTVDS_OS_USERNAME`
- `HOSTVDS_OS_PASSWORD`
- `HOSTVDS_OS_PROJECT_NAME`
- `HOSTVDS_OS_USER_DOMAIN_NAME` or `HOSTVDS_OS_USER_DOMAIN_ID`
- `HOSTVDS_OS_PROJECT_DOMAIN_NAME` or `HOSTVDS_OS_PROJECT_DOMAIN_ID`
- `HOSTVDS_OS_REGION_NAME`
- `HOSTVDS_OS_INTERFACE`

Get existing `server_id` (PowerShell):

```powershell
.\scripts\core\get-hostvds-server-id.ps1 -EnvPath .\.env
```

Alternative:
- `https://horizon.hostvds.com` -> `Compute` -> `Instances` -> `ID`.

## Lifecycle semantics

- `enabled = false`: node removed from desired cluster, VPS remains.
- Remove key from `hostvds_provisioned_vpn_nodes`: VPS is destroyed.

## Adding another VPN provider

Add a provider-specific module following
`terraform/nodes/modules/provider-template/README.md` and merge its normalized
output into `terraform/nodes` root. This keeps provider swap/multi-provider
operation declarative without changing Ansible logic.
