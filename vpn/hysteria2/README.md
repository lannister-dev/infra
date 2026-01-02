# Hysteria2 (fallback for whitelist networks)

This is a UDP/443 QUIC-based fallback channel intended to work when HTTPS/TCP is partially blocked (whitelist mode).

## Install (on DE vpn node)
- Ensure `.env` contains:
  - HY2_AUTH_PASSWORD
  - HY2_OBFS_PASSWORD
  - HY2_LISTEN_PORT (optional, default 443)
  - HY2_SNI (optional)

Run:
```bash
sudo bash vpn/hysteria2/install.sh