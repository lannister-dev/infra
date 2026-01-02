# Cloudflare for VLESS (WS+TLS)

## DNS
Create A record:
- Name: vpn
- Target: <DE_SERVER_PUBLIC_IP>
- Proxy status: Proxied (orange cloud)

## SSL/TLS
- Mode: Full (strict)
- Edge Certificates: keep defaults

## WAF / Rules
Allow WebSockets is enabled by default on Cloudflare.

## Notes
- Client connects to: vpn.<domain>
- WS path: /api/v1/stream
- Origin is Nginx on DE server, Xray behind it on 127.0.0.1:10000