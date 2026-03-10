# VPN Node Lifecycle

Canonical lifecycle for VPN nodes:

1. `drain`
2. `migrate`
3. `deactivate`

`delete/recreate` is not the default operating model.

## Node identity

Use one control-plane node identity everywhere:

- `node_key = swarm hostname`
- runtime sets `AGENT_NODE_KEY={{.Node.Hostname}}`
- control-plane reconciliation uses `PATCH /agent/nodes/by-key/{hostname}`
- `peer_name` remains the WireGuard and Swarm peer label only

Do not mix hostname, `peer_name`, provider server id, and IP as interchangeable node identifiers.
`reconcile-vpn-nodes.yml` now enforces system hostname = `peer_name`, so catalog name and runtime node key stay aligned.

## Lifecycle

### 1. Drain

- `docker node update --availability drain <node>`
- wait until traffic and tasks move away
- keep node-agent record intact

### 2. Migrate

- add replacement node in Terraform catalog
- apply `terraform/nodes`
- run `reconcile-vpn-nodes.yml`
- run deploy workflow
- verify health, peer config, and control-plane reconciliation

### 3. Deactivate

- set old node `enabled = false` in catalog
- apply `terraform/nodes`
- run reconcile again so WireGuard and Swarm desired state drop the old node
- remove underlying VM only as a controlled follow-up action

## Forbidden as normal practice

- `REPLACE_VPN_NODES`
- force `terraform -replace` for active VPN nodes
- delete service records before traffic migration is complete

## Exception handling

For unrecoverable provider or disk failure:

1. add replacement first if possible
2. migrate traffic
3. deactivate old node in catalog
4. remove failed compute only after state is stable
