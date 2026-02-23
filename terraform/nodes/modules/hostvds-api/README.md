# HostVDS API Module

Resolves `public_ip` for VPN nodes from HostVDS OpenStack API
(Keystone + Compute) and returns normalized `vpn_nodes` map.

Inputs:

- `enabled`
- `os_auth_url`
- `os_username`
- `os_password`
- `os_project_name`
- `os_user_domain_name`
- `os_user_domain_id` (optional, overrides name)
- `os_project_domain_name`
- `os_project_domain_id` (optional, overrides name)
- `os_region_name` (optional)
- `os_interface` (`public` by default)
- `nodes` map keyed by peer name

Output:

- `vpn_nodes` map compatible with `terraform/nodes` root variable schema.
