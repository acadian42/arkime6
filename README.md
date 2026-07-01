# fpc_production_build_arikme

Production-grade, **Dockerized Arkime 6 Full-Packet-Capture cluster**, deployed by **Ansible** and
operated through **AWX**, validated in a **Vagrant + VMware** lab that reuses the same roles.

> The directory name is intentionally misspelled (`arikme`). The product is **Arkime**, spelled
> correctly everywhere else.

## Topology

| Group | Count | Role |
|---|---|---|
| `elasticsearch_physical_hosts` (`es-phys-01..05`) | 5 × 125 GiB | Run **N ES containers/host** (N∈{3,4,5}, default 3) → 15/20/25 nodes |
| `arkime_recorders` (`arkime-rec-01..05`) | 5 | Arkime Capture + Viewer + Nginx(LDAP) + ldap-auth sidecar |

## Pinned versions (verified 2026-06-24 — see `docs/_sources/`)

| Component | Pin |
|---|---|
| Arkime | `ghcr.io/arkime/arkime/arkime@sha256:083fc1af…2895c66` (v6.5.0) |
| Elasticsearch | `docker.elastic.co/elasticsearch/elasticsearch:8.19.17` (+ digest) |
| Nginx / LDAP daemon | `nginx:1.27-alpine` / `caltechads/nginx-ldap-auth-service:2.6.2` |
| ansible-core / community.docker / awx.awx | 2.21.1 / 5.2.1 / 24.6.1 |
| Vagrant / vagrant-vmware-desktop | 2.4.9 / 3.0.5 |

## Quick start (lab)

```bash
ansible-galaxy collection install -r requirements.yml -p collections
cd vagrant && vagrant up --provider vmware_desktop          # functional profile
# or run Ansible directly against the lab inventory:
ansible-playbook -i inventories/vagrant/hosts.yml playbooks/site.yml
```

## Production (via AWX)

Production runs through the AWX workflow in `awx/workflow/`. Direct CLI (break-glass):

```bash
cp inventories/production/hosts.example.yml inventories/production/hosts.yml   # edit
ansible-playbook playbooks/preflight.yml
ansible-playbook playbooks/site.yml --tags elasticsearch
# Arkime DB init is GATED: requires -e arkime_force_init=true and an AWX approval
ansible-playbook playbooks/initialize_arkime.yml -e arkime_force_init=true
ansible-playbook playbooks/site.yml --tags recorders,nginx
ansible-playbook playbooks/validate.yml
```

## Safety rails

- **Density is benchmarked, not assumed.** Default `elasticsearch_nodes_per_host: 3`; compare 3/4/5 with
  the harness in `tests/` before changing (see `docs/sizing.md`).
- **No destructive action without opt-in.** `confirm_destroy`, `arkime_force_init` default `false`; AWX
  approval nodes gate init/upgrade/recover. No playbook deletes data volumes by default.
- **Cluster cannot re-bootstrap on restart** — `cluster.initial_master_nodes` is removed after first
  formation and guarded by `{{ es_bootstrap_marker }}`.
- **No secrets in Git.** Values come from Ansible Vault / AWX credentials (`vault_*`).

See `docs/` for architecture, operations, authentication, sizing, upgrades, and disaster recovery.
# arkime6
