#!/usr/bin/env bash
# Step 2b — build the custom k8s container hook (the runner-container-hooks fork).
#
# The fork's packages/k8s bundles to a single ncc index.js that the runner loads
# as the k8s-novolume hook (ACTIONS_RUNNER_CONTAINER_HOOKS=.../k8s-novolume/index.js).
# It carries the custom features (work-volume PV reuse, node pinning, job
# resources/usage reporting, reliable output copy-back, ...).
#
# Output: ${ARTIFACTS_DIR}/hooks/k8s-novolume/index.js
#
# Sources, in priority order:
#   1. HOOKS_INDEX_JS env var pointing at a prebuilt bundle.
#   2. Build from source via HOOKS_REPO (default ../runner-container-hooks).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

HOOKS_REPO="${HOOKS_REPO:-${RUNNER_ROOT}/../runner-container-hooks}"
HOOKS_BUILDER_IMAGE="${HOOKS_BUILDER_IMAGE:-node:20-bookworm}"
HOOKS_OUT_DIR="${ARTIFACTS_DIR}/hooks/k8s-novolume"
HOOKS_OUT="${HOOKS_OUT_DIR}/index.js"

mkdir -p "${HOOKS_OUT_DIR}"

if [ -n "${HOOKS_INDEX_JS:-}" ]; then
  [ -f "${HOOKS_INDEX_JS}" ] || die "HOOKS_INDEX_JS not found at ${HOOKS_INDEX_JS}"
  log "hooks: using prebuilt bundle ${HOOKS_INDEX_JS}"
  cp "${HOOKS_INDEX_JS}" "${HOOKS_OUT}"
  log "hooks: -> ${HOOKS_OUT}"
  exit 0
fi

if [ -f "${HOOKS_OUT}" ] && [ "${FORCE_HOOKS_BUILD:-0}" != "1" ]; then
  log "hooks: already present (${HOOKS_OUT}) — skipping (set FORCE_HOOKS_BUILD=1 to rebuild)"
  exit 0
fi

require_docker
[ -d "${HOOKS_REPO}/packages/k8s" ] || die "custom hooks repo not found at ${HOOKS_REPO} (set HOOKS_REPO)"

log "hooks: building custom k8s hook from ${HOOKS_REPO}"
docker run --rm \
  --platform "${DOCKER_PLATFORM}" \
  -e HOME=/tmp/hooks-home \
  -v "${HOOKS_REPO}:/hooks-src:ro" \
  -v "${HOOKS_OUT_DIR}:/hooks-out" \
  "${HOOKS_BUILDER_IMAGE}" \
  bash -lc '
    set -euo pipefail
    mkdir -p /tmp/hooks-home /tmp/hooks-src
    cp -a /hooks-src/. /tmp/hooks-src
    cd /tmp/hooks-src
    rm -rf packages/*/node_modules node_modules
    npm ci --prefix packages/hooklib
    npm run build --prefix packages/hooklib
    npm ci --prefix packages/k8s
    npm run build --prefix packages/k8s
    cp packages/k8s/dist/index.js /hooks-out/index.js
  '

[ -f "${HOOKS_OUT}" ] || die "hooks: bundle was not produced"
log "hooks: -> ${HOOKS_OUT} ($(wc -c < "${HOOKS_OUT}") bytes)"
