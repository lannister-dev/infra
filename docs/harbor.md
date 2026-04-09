# Harbor Registry in This Infrastructure

## Purpose

Harbor is used in this infrastructure as a **private container registry** for storing, scanning, and distributing Docker images used by the platform.

It provides:
- Secure image storage
- Role-based access control (RBAC)
- Image vulnerability scanning
- Audit logs
- Replication and lifecycle policies

Harbor is treated as a **foundational infrastructure component**, not as an application workload.

---

## Deployment Model

### ❌ Why Harbor Is NOT Deployed in Docker Swarm

Harbor is **intentionally not deployed as a Docker Swarm stack**.

Reasons:

1. **Harbor is a stateful system**
   - PostgreSQL
   - Redis
   - Registry storage
   - Job logs
   - Certificates and secrets

   Swarm is not designed to reliably manage complex stateful applications without significant operational overhead.

2. **Harbor has its own lifecycle**
   - Upgrades
   - Backups
   - Disaster recovery
   - Storage layout

   Mixing Harbor lifecycle with Swarm application stacks creates coupling and operational risk.

3. **Official Harbor installation model**
   - Harbor is officially distributed as a Docker Compose–based system
   - This is the only fully supported and documented installation path

4. **Infrastructure boundary**
   - Swarm is used for **workloads**
   - Harbor is part of **platform infrastructure**

This separation keeps the infrastructure clean and predictable.

- **Traefik** runs in Docker Swarm
- **Harbor** runs via Docker Compose
- Traefik routes HTTPS traffic to Harbor’s Nginx container
- Harbor services communicate internally on their own Docker network

---

## Traefik Integration

Harbor is exposed through Traefik using a **file provider**, not Swarm labels.

This is intentional.

## Replacement Note

Changing the Harbor host IP in this repository only repoints Traefik.
It does **not** provision, install, or migrate Harbor itself.

A Harbor node replacement therefore requires two separate steps:
- provision the replacement VM;
- migrate Harbor Compose/data/secrets to that VM before switching Traefik to the new IP.
