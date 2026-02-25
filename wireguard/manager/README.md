# vpn-infra WireGuard Manager

Non-interactive WireGuard manager intended for infrastructure use (CI/bot/ops), not a “one-click VPN installer”.

## Goals
- Domain endpoint (no “curl my IP” autodetect)
- No Unbound / no resolv.conf hacks / no nftables magic
- Predictable files in `/etc/wireguard`
- Add/remove peers without `wg-quick down`

## Files
- Server config: `/etc/wireguard/wg0.conf`
- Server keys:
  - `/etc/wireguard/wg0.key`
  - `/etc/wireguard/wg0.pub`
- Client configs: `/etc/wireguard/clients/<name>-wg0.conf`

## Configure
Edit: `wireguard/manager/defaults.env`

Key settings:
- `WG_ENDPOINT`: domain name for clients (recommended)
- `WG_PORT`: 443 or 51820 (choose what is allowed)
- `WG_IPV4_SUBNET`: e.g. 10.100.0.0/24
- `WG_CLIENT_ALLOWED_IPS`: default routes pushed to clients (by default only wg-subnet)

## Usage
From `vpn-infra/wireguard`:
```bash
chmod +x apply.sh manager/wireguard-manager.sh

./apply.sh --install
./apply.sh --list

./apply.sh --add phone
./apply.sh --add laptop

./apply.sh --remove laptop

./apply.sh --backup
./apply.sh --restore /var/backups/wireguard-vpn-infra.zip <password>
```

## IaC integration

Production reconciliation path uses:
- `wireguard/manager/reconcile-peer.sh` (ensure peer + client config, idempotent, rc `10` on change)
- `wireguard/manager/decommission-peer.sh` (remove stale peer/node/config, idempotent, rc `10` on change)

These scripts are called by Ansible playbook `ansible/playbooks/reconcile-vpn-nodes.yml`.
`wireguard/apply.sh` is retained for legacy/manual operations only.
