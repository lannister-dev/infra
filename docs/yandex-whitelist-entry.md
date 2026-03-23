# Yandex Cloud Whitelist Entry Adoption

This flow adopts an already existing Yandex Cloud first-hop VPN entry node into
`terraform/nodes` without recreating the VM, changing its public IP, or moving it
to another availability zone.

Target resource type in Terraform: `yandex_whitelist_entry_nodes`.

Runtime class after reconcile/deploy:

- node joins Swarm as a normal worker
- node gets `traffic_role=whitelist_entry`
- node does not run regular backend `vpn_xray` / `vpn_node-agent`
- node runs dedicated `vpn-whitelist-entry` relay stack

## 1. Read current values from Yandex Cloud

Export Yandex credentials first:

```bash
export YC_TOKEN=...
export YC_CLOUD_ID=...
export YC_FOLDER_ID=...
```

Read the existing VM, address, and security group:

```bash
yc compute instance get <INSTANCE_ID> --full --format json > /tmp/yc-whitelist-instance.json
yc vpc address get <ADDRESS_ID> --format json > /tmp/yc-whitelist-address.json
yc vpc security-group get <SECURITY_GROUP_ID> --format json > /tmp/yc-whitelist-sg.json
```

Confirm these fields before touching Terraform:

- VM `zone_id` stays the current zone.
- VM `network_interfaces[0].primary_v4_address.one_to_one_nat.address` is `158.160.224.236`.
- Address object is the reserved static address attached to the same VM.
- Security group contains or can safely accept inbound `22/tcp` and `443/tcp`.
- Metadata still contains the current SSH key entry (`ssh-keys`) for the node.

Useful quick checks:

```bash
jq -r '.zone_id' /tmp/yc-whitelist-instance.json
jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address' /tmp/yc-whitelist-instance.json
jq -r '.external_ipv4_address.address' /tmp/yc-whitelist-address.json
jq -r '.id, .name' /tmp/yc-whitelist-sg.json
```

## 2. Declare the node in Terraform

Add the node into `terraform/nodes/catalog.auto.tfvars`:

```hcl
yandex_whitelist_entry_nodes = {
  "vpn-yc-whitelist-entry-01" = {
    instance_id         = "<INSTANCE_ID>"
    address_id          = "<ADDRESS_ID>"
    security_group_id   = "<SECURITY_GROUP_ID>"
    channel             = "prod"
    ssh_user            = "ubuntu"
    ssh_port            = 22
    ssh_key_ref         = "yc"
    enabled             = true
    region              = "ru-central1-a"
    platform_region     = "ru"
    ssh_ingress_cidrs   = ["0.0.0.0/0"]
    https_ingress_cidrs = ["0.0.0.0/0"]
    prevent_destroy     = true
  }
}
```

Notes:

- Keep the catalog key stable. It becomes the VPN peer/node identity.
- `prevent_destroy = true` is intentional for this class of node.
- The module preserves the imported VM/IP/SG settings from live cloud data and only adds Terraform ownership plus `whitelist_entry` labels/metadata.
- Runtime separation is handled later by Ansible + Swarm labels, not by Terraform alone.

## 3. Initialize Terraform

```bash
set -a
source .env
set +a

terraform -chdir=terraform/nodes init -input=false -backend-config="$(pwd)/terraform/backends/nodes.hcl"
```

## 4. Import existing resources into state

Import all three objects before running `plan`:

```bash
terraform -chdir=terraform/nodes import 'module.yandex_whitelist_entry[0].yandex_vpc_address.whitelist_entry["vpn-yc-whitelist-entry-01"]' <ADDRESS_ID>
terraform -chdir=terraform/nodes import 'module.yandex_whitelist_entry[0].yandex_vpc_security_group.whitelist_entry["vpn-yc-whitelist-entry-01"]' <SECURITY_GROUP_ID>
terraform -chdir=terraform/nodes import 'module.yandex_whitelist_entry[0].yandex_compute_instance.whitelist_entry["vpn-yc-whitelist-entry-01"]' <INSTANCE_ID>
```

Recommended immediate state inspection:

```bash
terraform -chdir=terraform/nodes state show 'module.yandex_whitelist_entry[0].yandex_vpc_address.whitelist_entry["vpn-yc-whitelist-entry-01"]'
terraform -chdir=terraform/nodes state show 'module.yandex_whitelist_entry[0].yandex_vpc_security_group.whitelist_entry["vpn-yc-whitelist-entry-01"]'
terraform -chdir=terraform/nodes state show 'module.yandex_whitelist_entry[0].yandex_compute_instance.whitelist_entry["vpn-yc-whitelist-entry-01"]'
```

## 5. Check the plan before any apply

Run:

```bash
terraform -chdir=terraform/nodes plan -input=false
```

Safe/expected outcomes:

- No `-/+` replace for `yandex_compute_instance.whitelist_entry`.
- No `-/+` replace for `yandex_vpc_address.whitelist_entry`.
- No zone change for the instance.
- No NAT IP change away from `158.160.224.236`.
- At most in-place updates for labels/metadata and SG rules.

If the plan wants replacement, stop and compare:

```bash
terraform -chdir=terraform/nodes state show 'module.yandex_whitelist_entry[0].yandex_compute_instance.whitelist_entry["vpn-yc-whitelist-entry-01"]'
yc compute instance get <INSTANCE_ID> --full --format json
```

The usual causes are wrong imported IDs, wrong catalog key, or an SSH metadata mismatch.

## 6. Reconcile node labels and deploy relay runtime

Set relay upstream for the first-hop node:

```bash
export VPN_WHITELIST_ENTRY_UPSTREAM_HOST=<backend_ip_or_dns>
export VPN_WHITELIST_ENTRY_UPSTREAM_PORT=443
```

Then run the normal node reconcile/deploy cycle:

```bash
export REPO_ROOT="$(pwd)"
export ANSIBLE_CONFIG="$(pwd)/ansible/ansible.cfg"

ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/reconcile-vpn-nodes.yml
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/deploy-stacks.yml
```

Expected runtime result:

- node is present in Swarm as worker
- node labels include `traffic_role=whitelist_entry`
- regular `vpn` / `vpn-dev` backend stacks do not schedule there
- `vpn-whitelist-entry` relay schedules there and publishes `443/tcp` in host mode

## 7. Verification checklist

- IP did not change: VM still uses `158.160.224.236`.
- VM is not planned for recreate.
- SG allows inbound `22/tcp`.
- SG allows inbound `443/tcp`.
- VM remains in the original availability zone.
- `terraform plan` is clean or only shows explainable in-place label/metadata/SG rule updates.
- `docker node inspect <node> --format '{{ json .Spec.Labels }}'` shows:
  - `role=vpn`
  - `channel=prod`
  - `peer_name=<peer>`
  - `traffic_role=whitelist_entry`
- `docker service ps vpn_xray` does not place tasks on the whitelist entry node.
- `docker service ps vpn_node-agent` does not place tasks on the whitelist entry node.
- `docker service ps vpn-whitelist-entry_relay` shows a task on the whitelist entry node.
