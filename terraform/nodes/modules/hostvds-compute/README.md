# HostVDS Compute Module

Creates VPN compute instances in HostVDS OpenStack and returns a map compatible
with `modules/hostvds-api` input (`server_id`, channel/user metadata).

This module only provisions instances. Public IP resolution is delegated to
`modules/hostvds-api`.
