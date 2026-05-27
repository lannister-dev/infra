# Node Role Swap Runbook

How to safely change a VPN node's role (entry ↔ backend) or move it between
environments (dev ↔ prod). Written after the 2026-05-27 prod incident where an
ad-hoc rotation left wg-mesh, sing-box, and subscription assignments in a
desynchronised state for ~4 hours.

## Concepts that bite

Each VPN node has state in **five** independent layers. A role swap touches
every layer; skipping any of them causes silent breakage that only surfaces
when probes (or users) start failing.

| Layer | Storage | What lives here |
|---|---|---|
| Control-plane | Postgres `vpn_node`, `user_placement`, `entry_backend_assignment`, `route` | Roles, peerings, declared routes |
| Subscription cache | Postgres `subscription_route_assignment` | Per-user pinned entry — survives `vpn_node.role` changes silently |
| K3s scheduling | Node labels (`channel`, `traffic_role`, `role=vpn`) | Which DaemonSet pods land on this node |
| Agent identity | Host filesystem (`/var/lib/go-node-agent`, `/var/lib/node-agent`, `/data`) | Badger/JSON identity bound to a specific control-api; survives pod restart |
| Wg-mesh runtime | Wireguard `wg0` interface + KV buckets `agent-wg-pubkeys`, `wg-mesh-peers` | Live peer list, IP allocations |

Sing-box shared config (`/var/lib/sing-box-shared/config.json`, hostPath)
is a derived artefact, but its init-container is **copy-if-absent** — so stale
bootstrap config from the previous role persists across pod restarts unless
manually wiped.

## Hard rules

1. **Never change `vpn_node.role` directly** without going through the steps
   below. The change cascades through six tables and one host filesystem; a
   bare `UPDATE` leaves orphans in all of them.
2. **Drain placements before touching role.** If you flip a backend to entry,
   every user with an active placement on it gets routed to an inbound that
   doesn't exist, and your tunnel dies on the next reconcile.
3. **Wipe agent state on every cluster/role move.** Identity in Badger/JSON
   binds the agent to a specific control-api node-id. Carrying it across a
   swap makes the new control-api treat the agent as foreign.
4. **Wipe `/var/lib/sing-box-shared/*` on entry-mode flip.** The init-container
   only copies the bootstrap if the file is missing, so old `listen_port` or
   stale users persist.
5. **Hold off on Reality changes on prod.** Test sni / public_key / short_id
   rotations on dev first — clients cache their old profile and pulling new
   subscription doesn't reset their stored server.
6. **Two NetGrid entries are not "diverse".** RU ISPs DPI by IP range; if your
   only two entries share an ASN/datacenter, one IP-block in their list takes
   both down. Always keep entries split across at least two providers.

## Standard role-swap procedure

For a single node `N` going from role `R_old` to `R_new` (e.g. backend → entry).

### 1. Drain users from the node (if it's currently a backend)

```sql
UPDATE user_placement
SET desired_state='inactive',
    op_version=op_version+1,
    last_migration_reason='manual_role_swap',
    updated_at=now()
WHERE backend_node_id = (SELECT id FROM vpn_node WHERE name = '<N>')
  AND desired_state = 'active'
  AND is_active = true;
```

Wait for entries to apply this (check `applied_state='applied'`).

### 2. Tear down peering rows

```sql
-- Assignments where this node is on either side
UPDATE entry_backend_assignment
SET is_active=false, enabled=false, updated_at=now()
WHERE entry_node_id   = (SELECT id FROM vpn_node WHERE name='<N>')
   OR backend_node_id = (SELECT id FROM vpn_node WHERE name='<N>');

-- Routes that reference this node
UPDATE route
SET is_active=false, updated_at=now()
WHERE entry_node_id = (SELECT id FROM vpn_node WHERE name='<N>')
   OR node_id       = (SELECT id FROM vpn_node WHERE name='<N>');

-- Stale subscription pins (clients still expecting this node as their entry)
DELETE FROM subscription_route_assignment
WHERE entry_node_id = (SELECT id FROM vpn_node WHERE name='<N>');
```

### 3. Update role

```sql
UPDATE vpn_node
SET role='<R_new>',
    is_draining=false,
    public_domain = CASE WHEN '<R_new>' = 'entry' THEN '' ELSE public_domain END,
    updated_at=now()
WHERE name = '<N>';
```

`public_domain` MUST be cleared when role becomes entry — the subscription
URI builder prefers it over `reality_ip`, and a CDN-fronted domain there
means clients will connect to the CDN instead of the node.

### 4. Wipe agent state on the host

SSH to the node:

```bash
# Go-agent
rm -rf /var/lib/go-node-agent/*

# Python agent
rm -rf /var/lib/node-agent/* /data/* 2>/dev/null

# Sing-box shared config (only if node will run sing-box now)
rm -rf /var/lib/sing-box-shared/*

# Wg-mesh keys (only if changing identity / moving cluster)
rm -rf /var/lib/wg-mesh/*
```

Pin the right paths — different agents store identity differently and
forgetting one means the agent re-uses a stale node-id.

### 5. Re-label the node in k3s

```bash
kubectl label node <hostname> \
  traffic_role=<entry|backend> \
  channel=<dev|prod> \
  role=vpn \
  --overwrite
```

`channel` is the easy one to forget. Without it, the role-specific
DaemonSet `nodeSelector` (`channel: prod, role: vpn`) doesn't match and the
node sits idle with only `node-exporter` running.

### 6. Wait for agent bootstrap

The new pod will hit `/api/v1/agent/initial` with no existing badger →
control-api inserts a fresh `vpn_node` row with auto-generated name like
`node-<ip-with-dashes>-<truncated-hostname>`.

Verify:

```sql
SELECT id, name, role, region, reality_ip, is_active
FROM vpn_node ORDER BY created_at DESC LIMIT 5;
```

### 7. Rename and fill in geographic / network fields

```sql
UPDATE vpn_node
SET name='<your-name>',
    region='<region>',
    reality_ip='<public IP>',
    updated_at=now()
WHERE name='<auto-generated-name>';
```

Keep node names role-suffixed (`fra-entry-01`, `par-backend-01`) — leaving an
old name like `rix-backend-01` on a node that is now an entry makes admin UI
and probe labels misleading.

### 8. Wire the new peerings + routes

```sql
-- entry_backend_assignment for the new role
INSERT INTO entry_backend_assignment
  (id, entry_node_id, backend_node_id, weight, enabled, is_active, rank, created_at, updated_at)
SELECT gen_random_uuid(), e.id, b.id, 100, true, true, 0, now(), now()
FROM vpn_node e, vpn_node b
WHERE e.name IN (<entry list>) AND b.name IN (<backend list>)
ON CONFLICT (entry_node_id, backend_node_id) DO UPDATE
  SET is_active=true, enabled=true, updated_at=now();

-- Reality routes
WITH reality AS (SELECT id FROM transport_profile WHERE name='reality_tcp_v1'),
     pairs  AS ( <select entry, backend pairs as above> )
INSERT INTO route (id, name, node_id, entry_node_id, transport_profile_id,
                   health_status, base_weight, effective_weight, is_active,
                   created_at, updated_at)
SELECT gen_random_uuid(),
       e.name || '→' || b.name || '·reality',
       b.id, e.id, reality.id,
       'healthy', 50, 50, true, now(), now()
FROM pairs (e, b), reality
ON CONFLICT (name) DO UPDATE SET is_active=true, health_status='healthy', updated_at=now();
```

### 9. Force-snapshot affected nodes

After role swap, entry-mode pool-entry agents on **other** nodes have stale
placement maps. Trigger snapshot:

```bash
KEY=$(grep ^ADMIN_API_KEY= /Users/lannister/dev/infra/.env | cut -d= -f2)
for NAME in <list-of-entries>; do
  NID=$(psql ... -tA -c "SELECT id FROM vpn_node WHERE name='$NAME';")
  curl -X POST -H "Authorization: Bearer $KEY" \
    https://api.lannister-dev.ru/api/v1/admin/transport/nodes/$NID/request-snapshot
done
```

### 10. Verify wg-mesh end-to-end

The most common silent failure mode: `wg setconf` reapplies peers but doesn't
re-assign the interface IP. Check from a wg-pod **on a peer node**:

```bash
kubectl -n vpn-prod exec <wg-mesh-pod-on-some-other-node> -- \
  nc -zv -w 3 <new-node-internal-wg-ip> 10100
```

If timeout, SSH to the new node and `ip addr show wg0` — if there is no
`inet` line, restart the wg-mesh pod on that node (`kubectl delete pod
<wg-mesh-pod>`). The init container runs `wg-quick up` which reads `Address=`
from the config, but the running container's `wg syncconf` does not.

### 11. Final smoke test

* `is_reachable=true` on probe-prod-entry for `*·reality` routes to the new
  node — within 60 seconds of snapshot.
* Live VPN session counter on the entry side ≥ pre-swap count after 5 min.

If `·pool` probes stay red but `·reality` passes — that is a Python
pool-entry agent quirk (single outbound per user instead of urltest group),
not a user-facing issue. Documented separately.

## Don'ts

* **Do not** click "Snapshot" in admin UI and assume it propagates to other
  entries. It snapshots one node at a time; you must trigger it per entry that
  needs to see the new placement layout.
* **Do not** assume the admin UI "Drain" button writes to `vpn_node.is_draining`.
  As of 2026-05-27 it can render the orange badge without the PATCH reaching
  control-api — verify with SQL.
* **Do not** copy `internal_wg_ip` between nodes. Each agent registers its
  own wg pubkey via NATS KV; the allocator assigns a new `/32` from the mesh
  CIDR (`10.10.0.0/24`). Forcing a specific IP causes pubkey/IP mismatch.
* **Do not** enable a HostVDS node and another HostVDS node in the same
  mesh expecting wg between them to work. Same-provider UDP between HostVDS
  VPS is filtered. HostVDS↔NetGrid/TimeWeb works; HostVDS↔HostVDS does not.

## Automation backlog

What we should build to make this runbook obsolete (with code, not docs):

1. **Wg-mesh address self-healing** in the wg-pod loop: after each `syncconf`,
   parse `Address=` from the config and `ip addr add` it (idempotent) if not
   already present.
2. **Route auto-creator reconciler** in control-api: for every active
   `entry_backend_assignment` ensure a Reality route row exists; deactivate
   routes whose assignment was removed.
3. **`subscription_route_assignment` invalidator**: after any `vpn_node.role`
   update, DELETE assignments where the referenced node no longer matches the
   subscription's required role.
4. **Atomic role-swap admin endpoint**: one POST that runs steps 1–3 in a
   transaction and queues steps 4–9 as a background job, with idempotency.
5. **K3s label validator**: deny `vpn_node.role` change if the corresponding
   node lacks `channel=<env>` label — fail fast instead of silently sitting
   pod-less.
6. **Pool-entry agent**: rebuild `auto-{uuid}` urltest groups consistently
   (all active placements, not just first).
7. **HostVDS-pair guard**: control-api refuses to add a second HostVDS-asn
   peer to wg-mesh unless an override flag is set.

These belong in the control-api / wg-mesh-chart, not in this runbook.
