#!/usr/bin/env bash
# Step 2b — build the custom k8s container hook (the runner-container-hooks fork).
#
# The fork's packages/k8s bundles to a single ncc index.js that the runner loads
# as the k8s-novolume hook (ACTIONS_RUNNER_CONTAINER_HOOKS=.../k8s-novolume/index.js).
# It carries the custom features (work-volume PV reuse, node pinning, job
# resources/usage reporting, reliable output copy-back, ...).
#
# Output: ${ARTIFACTS_DIR}/hooks/k8s-novolume/index.js
#         ${ARTIFACTS_DIR}/hooks/k8s-novolume/job-started.sh — the runner's
#         job-started hook beside it (packages/k8s/job-started.sh of the fork):
#         every job's "Set up runner" step says which node its runner pod runs on
#
# HOOKS_JOB_STARTED_SH points at another job-started.sh (with HOOKS_INDEX_JS
# and no fork checkout, say).
#
# Sources, in priority order:
#   1. HOOKS_INDEX_JS env var pointing at a prebuilt bundle.
#   2. Build from source via HOOKS_REPO (default ../runner-container-hooks).
#
# The bundle's last line records what it was built from:
#   // k8s-novolume hook source: <hooks commit>
# A previously built bundle is reused only when that line names the exact
# commit HOOKS_REPO is on now, with a clean working tree. Any other case —
# new commit, uncommitted changes, a prebuilt bundle, a bundle without the
# line — rebuilds it. FORCE_HOOKS_BUILD=1 always rebuilds. The same line lets
# an image be checked with:
#   docker run --rm --entrypoint tail <image> -n1 /home/runner/k8s-novolume/index.js
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

HOOKS_REPO="${HOOKS_REPO:-${RUNNER_ROOT}/../runner-container-hooks}"
HOOKS_BUILDER_IMAGE="${HOOKS_BUILDER_IMAGE:-node:20-bookworm}"
HOOKS_OUT_DIR="${ARTIFACTS_DIR}/hooks/k8s-novolume"
HOOKS_OUT="${HOOKS_OUT_DIR}/index.js"
# Where the build container drops its raw bundle (owned by root).
HOOKS_BUILD_OUT="${HOOKS_OUT}.build"
SOURCE_MARKER='// k8s-novolume hook source: '

mkdir -p "${HOOKS_OUT_DIR}"

# Install a bundle as ${HOOKS_OUT} with its source appended as the last line.
# Written to a temp file and moved into place, so ${HOOKS_OUT} only ever exists
# complete — a bundle without the line is never reused — and is owned by the
# invoking user even though the build container writes as root.
install_bundle() {
  { cat "$1"; printf '\n%s%s\n' "${SOURCE_MARKER}" "$2"; } > "${HOOKS_OUT}.tmp"
  mv -f "${HOOKS_OUT}.tmp" "${HOOKS_OUT}"
}

# The job-started hook, from the fork the bundle comes from; refreshed on every
# run — it is one small file, and a reused bundle's commit is its commit too.
install_job_started() {
  local source="${HOOKS_JOB_STARTED_SH:-${HOOKS_REPO}/packages/k8s/job-started.sh}"
  [ -f "${source}" ] || die "job-started hook not found at ${source} (set HOOKS_JOB_STARTED_SH, or update the hooks fork)"
  install -m 0755 "${source}" "${HOOKS_OUT_DIR}/job-started.sh"
  log "hooks: -> ${HOOKS_OUT_DIR}/job-started.sh"
}

# Drop every earlier output (rm only needs the directory to be writable, so
# this also clears root-owned files from a previous container build). The
# .source file is the stamp format of an earlier version of this script.
clean_outputs() {
  rm -f "${HOOKS_OUT}" "${HOOKS_OUT}.tmp" "${HOOKS_BUILD_OUT}" "${HOOKS_OUT}.source"
}

if [ -n "${HOOKS_INDEX_JS:-}" ]; then
  [ -f "${HOOKS_INDEX_JS}" ] || die "HOOKS_INDEX_JS not found at ${HOOKS_INDEX_JS}"
  warn "hooks: using prebuilt bundle ${HOOKS_INDEX_JS} — its source is not verified"
  clean_outputs
  # Never matches a commit, so the next source build replaces it.
  install_bundle "${HOOKS_INDEX_JS}" "prebuilt ${HOOKS_INDEX_JS}"
  log "hooks: -> ${HOOKS_OUT}"
  install_job_started
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
BUILT_SOURCE="$(tail -n1 "${HOOKS_OUT}" 2>/dev/null | sed -n "s#^${SOURCE_MARKER}##p" || true)"

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
  install_job_started
  exit 0
fi

# Drop the old bundle first, so a failed build can never leave it in place for
# the image step to pick up.
clean_outputs

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
    cp packages/k8s/dist/index.js /hooks-out/index.js.build
  '

[ -f "${HOOKS_BUILD_OUT}" ] || die "hooks: bundle was not produced"
install_bundle "${HOOKS_BUILD_OUT}" "${HOOKS_SOURCE}"
rm -f "${HOOKS_BUILD_OUT}"
log "hooks: -> ${HOOKS_OUT} ($(wc -c < "${HOOKS_OUT}") bytes, source ${HOOKS_SOURCE})"
install_job_started
