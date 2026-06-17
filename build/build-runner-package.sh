#!/usr/bin/env bash
# Step 2 — build the custom runner from src/ and bake the custom Node binaries
# into its externals (node20 + node24), then package it.
#
# The runner mounts externals/ into the job container, so replacing the bundled
# node with the glibc-2.27 build is what makes JS actions run inside an
# ubuntu:18.04 job container without the "GLIBC_2.28 not found" error.
#
# Output: ${RUNNER_PACKAGE}  (a full actions-runner layout tarball)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_docker

BUILD_CONFIG="${BUILD_CONFIG:-Release}"
BUILDER_IMAGE="${BUILDER_IMAGE:-mcr.microsoft.com/dotnet/sdk:8.0}"

[ -f "${NODE_DIST_DIR}/node20.tar.gz" ] || die "missing ${NODE_DIST_DIR}/node20.tar.gz — run build-node-binaries.sh first"
[ -f "${NODE_DIST_DIR}/node24.tar.gz" ] || die "missing ${NODE_DIST_DIR}/node24.tar.gz — run build-node-binaries.sh first"

mkdir -p "${ARTIFACTS_DIR}"
rm -f "${RUNNER_PACKAGE}"

log "Building custom runner package (${BUILD_CONFIG}/${RUNTIME_ID}) with custom node baked in"
docker run --rm \
  --platform "${DOCKER_PLATFORM}" \
  -u "$(id -u):$(id -g)" \
  -e BUILD_CONFIG="${BUILD_CONFIG}" \
  -e RUNTIME_ID="${RUNTIME_ID}" \
  -e HOME=/tmp/runner-home \
  -e DOTNET_CLI_HOME=/tmp/runner-home \
  -e NUGET_PACKAGES=/tmp/runner-home/.nuget \
  -v "${RUNNER_ROOT}:/runner-src:ro" \
  -v "${NODE_DIST_DIR}:/node-dist:ro" \
  -v "${ARTIFACTS_DIR}:/runner-out" \
  "${BUILDER_IMAGE}" \
  bash -lc '
    set -euo pipefail
    mkdir -p /tmp/runner-home
    cp -a /runner-src/. /tmp/runner-src
    rm -rf /tmp/runner-src/_dotnetsdk /tmp/runner-src/_layout /tmp/runner-src/_package /tmp/runner-src/_downloads
    cd /tmp/runner-src/src

    ./dev.sh layout "${BUILD_CONFIG}" "${RUNTIME_ID}"

    echo "==> Replacing bundled node20/node24 with custom glibc-2.27 builds"
    for v in node20 node24; do
      target="/tmp/runner-src/_layout/externals/${v}"
      rm -rf "${target}"
      mkdir -p "${target}"
      tar -xzf "/node-dist/${v}.tar.gz" --strip-components=1 -C "${target}"
      chmod +x "${target}/bin/node"
    done

    echo "==> Verifying injected node binaries"
    /tmp/runner-src/_layout/externals/node20/bin/node --version
    /tmp/runner-src/_layout/externals/node24/bin/node --version

    ./dev.sh package "${BUILD_CONFIG}" "${RUNTIME_ID}"

    PACKAGE_FILE="$(find /tmp/runner-src/_package -maxdepth 1 -type f -name "actions-runner-${RUNTIME_ID}-*.tar.gz" | sort | tail -n 1)"
    [ -n "${PACKAGE_FILE}" ] || { echo "runner package not produced" >&2; exit 1; }
    cp "${PACKAGE_FILE}" /runner-out/actions-runner.tar.gz
  '

[ -f "${RUNNER_PACKAGE}" ] || die "runner package export failed"
log "Custom runner package ready: ${RUNNER_PACKAGE}"
ls -la "${RUNNER_PACKAGE}"
