#!/usr/bin/env bash
# Step 1 — produce glibc-2.27-compatible Node.js binaries for Ubuntu 18.04.
#
# Output: ${NODE_DIST_DIR}/node20.tar.gz and ${NODE_DIST_DIR}/node24.tar.gz
#         (standard `node-vX-linux-x64` layout: bin/ include/ lib/ share/)
#
# Sources, in priority order:
#   1. NODE20_TARBALL / NODE24_TARBALL env vars pointing at prebuilt tarballs
#      (fastest — e.g. downloaded from a node20-ubuntu1804 GitHub Release).
#   2. Build from source via the node20-ubuntu1804 repo's build-local.sh
#      (NODE_REPO, default ../node20-ubuntu1804). Slow under emulation.
#
# A tarball already in ${NODE_DIST_DIR} is reused only while it holds the Node
# version the runner pins (src/Misc/externals.sh): a runner upgrade that moves
# the pin replaces it, so the package never ships the Node of an older runner.
# FORCE_NODE_BUILD=1 replaces it whatever it holds.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

NODE_REPO="${NODE_REPO:-${RUNNER_ROOT}/../node20-ubuntu1804}"

resolve_node_versions
mkdir -p "${NODE_DIST_DIR}"

# The Node version a tarball holds, without the v: the name of its top
# directory says it (`node-v24.22.1-linux-x64/`, as nodejs.org and
# node20-ubuntu1804 pack it). Empty for a tarball that names none.
tarball_node_version() {
  { tar -tzf "$1" 2>/dev/null || true; } |
    sed -nE '1s#^(\./)?node-v([0-9]+\.[0-9]+\.[0-9]+)-.*#\2#p'
}

# args: <version-without-v> <gcc> <label> <override-tarball-or-empty>
produce_node() {
  local version="$1" gcc="$2" label="$3" override="$4"
  local out="${NODE_DIST_DIR}/${label}.tar.gz"
  local have

  if [ -f "${out}" ] && [ "${FORCE_NODE_BUILD:-0}" != "1" ]; then
    have="$(tarball_node_version "${out}")"
    if [ "${have}" = "${version}" ]; then
      log "${label}: v${version} already present (${out}) — skipping (set FORCE_NODE_BUILD=1 to rebuild)"
      return
    fi
    # Gone before its replacement is made: a build that fails here leaves
    # nothing for the package step to ship by mistake.
    log "${label}: ${out} holds ${have:+Node v}${have:-no Node version it names}, the runner pins v${version} — replacing it"
    rm -f "${out}"
  fi

  if [ -n "${override}" ]; then
    [ -f "${override}" ] || die "${label}: tarball not found at ${override}"
    have="$(tarball_node_version "${override}")"
    [ "${have}" = "${version}" ] ||
      warn "${label}: ${override} holds ${have:+Node v}${have:-no Node version it names}, the runner pins v${version}"
    log "${label}: using prebuilt tarball ${override}"
    cp "${override}" "${out}"
    return
  fi

  [ -d "${NODE_REPO}" ] || die "${label}: node repo not found at ${NODE_REPO} (set NODE_REPO or provide a prebuilt tarball)"
  [ -x "${NODE_REPO}/build-local.sh" ] || die "${label}: ${NODE_REPO}/build-local.sh missing/not executable"

  log "${label}: building Node v${version} (gcc-${gcc}) from source via ${NODE_REPO}"
  ( cd "${NODE_REPO}" && DOCKER_PLATFORM="${DOCKER_PLATFORM}" PLATFORM="${DOCKER_PLATFORM}" ./build-local.sh "v${version}" "${gcc}" )

  local built
  built="$(find "${NODE_REPO}/dist/node-v${version}" -maxdepth 1 -name "node-v${version}-linux-x64.tar.gz" | head -1)"
  [ -n "${built}" ] || die "${label}: expected tarball not produced under ${NODE_REPO}/dist/node-v${version}"
  cp "${built}" "${out}"
  log "${label}: -> ${out}"
}

produce_node "${NODE20_VERSION}" 10 node20 "${NODE20_TARBALL:-}"
produce_node "${NODE24_VERSION}" 13 node24 "${NODE24_TARBALL:-}"

log "Node binaries ready in ${NODE_DIST_DIR}"
ls -la "${NODE_DIST_DIR}"
