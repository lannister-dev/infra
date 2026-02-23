# Timeweb Compute Module

Creates non-VPN infrastructure servers in Timeweb and returns normalized
`infra_nodes` map for inventory generation.

Uses resource `twc_server` from provider
`tf.timeweb.cloud/timeweb-cloud/timeweb-cloud`.

Input `nodes` supports both:
- `availability_zone` (preferred for placement)
- `location` (metadata fallback for region labeling)
