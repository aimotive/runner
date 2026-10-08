#!/usr/bin/env bash
# Step 2b — build the custom k8s container hook (the runner-container-hooks fork).
#
# The fork's packages/k8s bundles to a single ncc index.js that the runner loads
# as the k8s-novolume hook (ACTIONS_RUNNER_CONTAINER_HOOKS=.../k8s-novolume/index.js).
# It carries the custom features (work-volume PV reuse, node pinning, job
# resources/usage reporting, reliable output copy-back, ...).
#
# Output: ${ARTIFACTS_DIR}/hooks/k8s-novolume/index.js
#         ${ARTIFACTS_DIR}/hooks/k8s-novolume/index.js.source  (what it was built from)
#
# Sources, in priority order:
#   1. HOOKS_INDEX_JS env var pointing at a prebuilt bundle.
#   2. Build from source via HOOKS_REPO (default ../runner-container-hooks).
#
# A previously built bundle is reused only when it was built from the exact
# commit HOOKS_REPO is on now, with a clean working tree. Any other case —
# new commit, uncommitted changes, a prebuilt bundle from an earlier run, a
# bundle without a source stamp — rebuilds it. FORCE_HOOKS_BUILD=1 always
# rebuilds. The source is also appended to the bundle as a trailing comment,
# so an image can be checked with:
#   docker run --rm --entrypoint tail <image> -n1 /home/runner/k8s-novolume/index.js
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

HOOKS_REPO="${HOOKS_REPO:-${RUNNER_ROOT}/../runner-container-hooks}"
HOOKS_BUILDER_IMAGE="${HOOKS_BUILDER_IMAGE:-node:20-bookworm}"
HOOKS_OUT_DIR="${ARTIFACTS_DIR}/hooks/k8s-novolume"
HOOKS_OUT="${HOOKS_OUT_DIR}/index.js"
HOOKS_STAMP="${HOOKS_OUT}.source"

mkdir -p "${HOOKS_OUT_DIR}"

# Record what the bundle was built from: next to it for the cache check, and
# inside it so the source can be read back from a built image.
stamp_bundle() {
  printf '%s\n' "$1" > "${HOOKS_STAMP}"
  printf '\n// k8s-novolume hook source: %s\n' "$1" >> "${HOOKS_OUT}"
}

if [ -n "${HOOKS_INDEX_JS:-}" ]; then
  [ -f "${HOOKS_INDEX_JS}" ] || die "HOOKS_INDEX_JS not found at ${HOOKS_INDEX_JS}"
  warn "hooks: using prebuilt bundle ${HOOKS_INDEX_JS} — its source is not verified"
  cp "${HOOKS_INDEX_JS}" "${HOOKS_OUT}"
  # Never matches a commit, so the next source build replaces it.
  stamp_bundle "prebuilt ${HOOKS_INDEX_JS}"
  log "hooks: -> ${HOOKS_OUT}"
  exit 0
fi

[ -d "${HOOKS_REPO}/packages/k8s" ] || die "custom hooks repo not found at ${HOOKS_REPO} (set HOOKS_REPO)"

# The hooks fork commit, with "-dirty" when the working tree has uncommitted
# (tracked or untracked) changes; "unknown" when it is not a git checkout.
HOOKS_SHA="$(git -C "${HOOKS_REPO}" rev-parse HEAD 2>/dev/null || echo unknown)"
HOOKS_SOURCE="${HOOKS_SHA}"
if [ "${HOOKS_SHA}" != unknown ] && [ -n "$(git -C "${HOOKS_REPO}" status --porcelain)" ]; then
  HOOKS_SOURCE="${HOOKS_SHA}-dirty"
fi
BUILT_SOURCE="$(cat "${HOOKS_STAMP}" 2>/dev/null || true)"

if [ "${FORCE_HOOKS_BUILD:-0}" = "1" ]; then
  reason="FORCE_HOOKS_BUILD=1"
elif ! [[ "${HOOKS_SOURCE}" =~ ^[0-9a-f]{40}$ ]]; then
  reason="source ${HOOKS_SOURCE} is not a clean commit"
elif [ ! -f "${HOOKS_OUT}" ]; then
  reason="no previous bundle"
elif [ "${BUILT_SOURCE}" != "${HOOKS_SOURCE}" ]; then
  reason="previous bundle was built from ${BUILT_SOURCE:-an unknown source}"
else
  log "hooks: bundle already built from ${HOOKS_SOURCE} — reusing ${HOOKS_OUT}"
  exit 0
fi

# Drop the old bundle first, so a failed build can never leave it in place for
# the image step to pick up.
rm -f "${HOOKS_OUT}" "${HOOKS_STAMP}"

require_docker
log "hooks: building custom k8s hook from ${HOOKS_REPO} at ${HOOKS_SOURCE} (${reason})"
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
    rm -rf packages/*/node_modules node_modules packages/*/lib packages/*/dist
    npm ci --prefix packages/hooklib
    npm run build --prefix packages/hooklib
    npm ci --prefix packages/k8s
    npm run build --prefix packages/k8s
    cp packages/k8s/dist/index.js /hooks-out/index.js
  '

[ -f "${HOOKS_OUT}" ] || die "hooks: bundle was not produced"
stamp_bundle "${HOOKS_SOURCE}"
log "hooks: -> ${HOOKS_OUT} ($(wc -c < "${HOOKS_OUT}") bytes, source ${HOOKS_SOURCE})"
