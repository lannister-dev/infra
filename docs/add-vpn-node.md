# Adding a new VPN node

## One command from manager

```bash
./scripts/add-node.sh <IP> --name <peer-name> [--channel dev|prod]
```

Example:

```bash
./scripts/add-node.sh 31.58.78.202 --name server-fin --channel prod
```

Options: `--channel dev|prod` (default: `prod`), `--user root` (default), `--port 22` (default).

## What it does

1. SSH into the server, installs Docker
2. Creates WireGuard peer on manager, pushes config to node, starts mesh
3. Joins node to Swarm, labels `role=vpn` + `channel=dev|prod`
4. Pushes Harbor registry auth to Swarm services

Scheduling rules:

- `docker/stacks/vpn-xray.yml` runs on `role=vpn` and `channel!=dev` (prod pool, xray + node-agent)
- `docker/stacks/vpn-xray-dev.yml` runs on `role=vpn` and `channel=dev` (dev pool, xray only)

## Prerequisites

- Root access on manager
- SSH key-based access to the new server (as root)
- Manager is logged into Harbor (`docker login harbor.lannister-dev.ru`)

## Verify

```bash
docker node ls
docker node inspect <node> --format '{{ json .Spec.Labels }}'
docker service ps vpn_xray --filter desired-state=running
docker service ps vpn-dev_xray --filter desired-state=running
```

## Deploy stacks

```bash
docker stack deploy -c docker/stacks/vpn-xray.yml vpn
docker stack deploy -c docker/stacks/vpn-xray-dev.yml vpn-dev
```

Notes:

- prod stack expects external Docker config `xray_config__V3_0` (created by `scripts/bootstrap.sh`).
- dev stack expects external Docker config `xray_config_dev__V2_9`.

## Troubleshooting

```bash
# Service not starting?
docker service ps vpn_xray --no-trunc
docker service ps vpn_node-agent --no-trunc
docker service ps vpn-dev_xray --no-trunc

# Logs
docker service logs vpn_xray --tail 50
docker service logs vpn_node-agent --tail 50
docker service logs vpn-dev_xray --tail 50

# WireGuard
wg show
ping 10.100.0.<X>
```
