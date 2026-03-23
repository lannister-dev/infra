# Yandex Cloud Whitelist Entry Module

Adopts an already existing Yandex Cloud first-hop VPN entry node into Terraform
without recreating the VM or changing its reserved public IP.

Managed resources:

- `yandex_compute_instance`
- `yandex_vpc_address`
- `yandex_vpc_security_group`

Inputs are existing resource IDs (`instance_id`, `address_id`, `security_group_id`).
The module reads current live settings through data sources, mirrors them into
resource configuration, and only adds Terraform ownership plus whitelist-entry
labels/metadata and guaranteed ingress rules for `22/tcp` and `443/tcp`.
