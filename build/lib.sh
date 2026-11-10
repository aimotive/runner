#!/usr/bin/env bash
# Shared helpers for the custom-runner build pipeline.
# Source this from the other build/*.sh scripts.

set -euo pipefail

# Repo root (parent of this build/ directory).
RUNNER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Where intermediate build artifacts (node tarballs, runner package) land.
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${RUNNER_ROOT}/build/.artifacts}"
NODE_DIST_DIR="${NODE_DIST_DIR:-${ARTIFACTS_DIR}/node}"
RUNNER_PACKAGE="${RUNNER_PACKAGE:-${ARTIFACTS_DIR}/actions-runner.tar.gz}"

# Common knobs.
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
RUNTIME_ID="${RUNTIME_ID:-linux-x64}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

require_docker() {
  command -v docker >/dev/null 2>&1 || die "docker is required but not found on PATH"
}

# Read the Node.js versions the runner pins, straight from its externals.sh,
# so the custom binaries always match what this runner expects.
#   exports NODE20_VERSION / NODE24_VERSION (e.g. 20.20.2 / 24.16.0)
resolve_node_versions() {
  local externals="${RUNNER_ROOT}/src/Misc/externals.sh"
  [ -f "$externals" ] || die "cannot find ${externals} to read pinned Node versions"

  NODE20_VERSION="${NODE20_VERSION:-$(grep -E '^NODE20_VERSION=' "$externals" | head -1 | cut -d'"' -f2)}"
  NODE24_VERSION="${NODE24_VERSION:-$(grep -E '^NODE24_VERSION=' "$externals" | head -1 | cut -d'"' -f2)}"

  [ -n "${NODE20_VERSION}" ] || die "could not determine NODE20_VERSION from externals.sh"
  [ -n "${NODE24_VERSION}" ] || die "could not determine NODE24_VERSION from externals.sh"
  export NODE20_VERSION NODE24_VERSION
}
