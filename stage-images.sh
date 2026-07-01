#!/usr/bin/env bash
# =============================================================================
# stage-images.sh — build-host helper for AIR-GAP image delivery.
#
# Pulls the four upstream FPC container images on an INTERNET-CONNECTED build
# host and writes each as a gzip'd `docker save` archive into ./images/ .
# The docker_engine role (image_delivery_mode: load_from_archive, the production
# default) then copies images/*.tar.gz to /opt/fpc/images on every target host
# and `docker load`s them; Compose runs with pull:never, so the air-gapped hosts
# never contact a registry.
#
# Run this on your build machine (NOT the air-gapped hosts). Then either:
#   * CLI deploys: leave images/ in place (it is image_archive_src = <repo>/images), or
#   * AWX deploys: mount/inject this images/ dir into the FPC Execution Environment
#     (images/ is gitignored, so it does NOT arrive via the Project's git sync).
#
# Usage:
#   ./stage-images.sh            # pull + save any images not already staged
#   ./stage-images.sh --force    # re-pull and overwrite existing archives
# =============================================================================
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"   # repo root — where images/ must live (image_archive_src)

FORCE=0
case "${1:-}" in
  --force) FORCE=1 ;;
  "") ;;
  *) echo "Usage: $0 [--force]" >&2; exit 2 ;;
esac

# The four upstream images. Keep in sync with
# inventories/production/group_vars/all.yml (arkime/es/nginx/ldap-auth).
# Arkime is digest-pinned. For reproducible air-gapped builds, pin the other
# three too: replace ":tag" with "@sha256:<digest>" after resolving with
#   docker buildx imagetools inspect <ref>
IMAGES=(
  "ghcr.io/arkime/arkime/arkime@sha256:083fc1af41bcad021eeb6b9cc630e26adae35690106d35e5193e4e8442895c66"
  "docker.elastic.co/elasticsearch/elasticsearch:8.19.17"
  "nginx:1.27-alpine"
  "caltechads/nginx-ldap-auth-service:2.6.2"
)

command -v docker >/dev/null 2>&1 \
  || { echo "ERROR: docker not found on this build host." >&2; exit 1; }
docker info >/dev/null 2>&1 \
  || { echo "ERROR: cannot reach the Docker daemon (running? are you in the docker group?)." >&2; exit 1; }

mkdir -p images

for ref in "${IMAGES[@]}"; do
  # docker save/load restores the real repo@digest|tag from tarball metadata;
  # the filename is cosmetic, so mangle the ref into a safe filename.
  name="$(printf '%s' "$ref" | tr '/:@' '___')"
  out="images/${name}.tar.gz"

  if [[ -s "$out" && "$FORCE" -ne 1 ]]; then
    echo "== skip (already staged): ${ref}"
    continue
  fi

  echo "== pull: ${ref}"
  docker pull "$ref"
  echo "== save: ${ref} -> ${out}"
  docker save "$ref" | gzip > "$out"
done

echo
echo "Staged archives in ./images :"
ls -lh images/*.tar.gz
count="$(find images -maxdepth 1 -name '*.tar.gz' | wc -l)"
echo
echo "Total: ${count} archive(s) (expected ${#IMAGES[@]})."
if (( count < ${#IMAGES[@]} )); then
  echo "WARNING: fewer archives than expected — review the pull output above." >&2
  exit 1
fi

cat <<'NEXT'

Done. Next step depends on how you deploy:
  * CLI:  archives are already at <repo>/images (image_archive_src); the
          docker_engine role docker-loads them on each host during deploy.
  * AWX:  images/ is gitignored and will NOT reach the Execution Environment
          via git. Mount/inject this images/ dir into the FPC EE, or the load
          step silently no-ops and Compose later fails on pull:never.
NEXT
