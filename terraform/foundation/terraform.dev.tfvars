enable_vpn_dev_stack = true

# Xray domains, paths and REALITY values must come from INFRA_ENV_DEV via TF_VAR_*.
# There is no inheritance/fallback between primary and dev config fields.
# Keep only non-secret dev workflow toggles in this repo var-file.
#
# Example:
# vpn_domain     = "dev.example.com"
# vpn_ws_path    = "/api/v1/stream"
# vpn_xhttp_path = "/api/v1/mobile"
# vpn_dev_domain = "dev-alt.example.com"
# vpn_dev_ws_path = "/api/v1/stream"
# vpn_dev_xhttp_path = "/api/v1/mobile"
#
# Set all real values in INFRA_ENV_DEV (TF_VAR_*).
# vpn_reality_server_name = "www.cloudflare.com"
# vpn_reality_private_key = "<x25519_private_key>"
# vpn_reality_short_id    = "<short_id_hex>"
# vpn_reality_dest_host   = "www.cloudflare.com"
