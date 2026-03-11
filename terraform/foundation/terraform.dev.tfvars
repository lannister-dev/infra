vpn_domain     = "dev.vpn.example.com"
vpn_ws_path    = "/api/v1/stream"
vpn_xhttp_path = "/api/v1/mobile"

# Dev endpoints for isolated transport testing.
enable_vpn_dev_stack = true
vpn_dev_domain       = "dev-vpn.example.com"
vpn_dev_ws_path      = "/api/v1/stream"
vpn_dev_xhttp_path   = "/api/v1/mobile"

# Set real values in INFRA_ENV_DEV (TF_VAR_*) for production-like REALITY testing.
# vpn_reality_server_name = "www.cloudflare.com"
# vpn_reality_private_key = "<x25519_private_key>"
# vpn_reality_short_id    = "<short_id_hex>"
# vpn_reality_dest_host   = "www.cloudflare.com"
