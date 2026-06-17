#!/usr/bin/env bash
# =============================================================================
# build-runner-image.sh — end-to-end builder for the custom GitHub Actions runner.
#
# Pipeline:
#   1. node     build glibc-2.27 node20/node24 (Ubuntu 18.04 compatible)
#   2. package  build the custom runner from src/ and bake that node into externals
#   3. native   build the native image  (images/Dockerfile.custom)
#   4. local    build the local image   (images/Dockerfile.local, myoung34 base)
#
# Usage:
#   ./build-runner-image.sh [all|node|package|images|native|local]   (default: all)
#
# Common overrides (env):
#   NODE_REPO=../node20-ubuntu1804        path to the custom-node repo (source build)
#   NODE20_TARBALL=/path/node20.tar.gz    use a prebuilt node tarball instead of building
#   NODE24_TARBALL=/path/node24.tar.gz
#   IMAGE_NATIVE_TAG=gha-runner-native:custom
#   IMAGE_LOCAL_TAG=gha-runner-local:custom
#   DOCKER_PLATFORM=linux/amd64
# =============================================================================
set -euo pipefail

BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/build" && pwd)"
source "${BUILD_DIR}/lib.sh"

IMAGE_NATIVE_TAG="${IMAGE_NATIVE_TAG:-gha-runner-native:custom}"
IMAGE_LOCAL_TAG="${IMAGE_LOCAL_TAG:-gha-runner-local:custom}"

build_image() {
  local dockerfile="$1" tag="$2"
  [ -f "${RUNNER_PACKAGE}" ] || die "runner package missing (${RUNNER_PACKAGE}) — run the 'package' step first"
  log "Building image ${tag} from ${dockerfile}"
  docker build \
    --platform "${DOCKER_PLATFORM}" \
    -f "${RUNNER_ROOT}/images/${dockerfile}" \
    -t "${tag}" \
    "${ARTIFACTS_DIR}"
  log "Built ${tag}"
}

cmd="${1:-all}"
require_docker

case "${cmd}" in
  node)
    "${BUILD_DIR}/build-node-binaries.sh"
    ;;
  package)
    "${BUILD_DIR}/build-runner-package.sh"
    ;;
  native)
    build_image Dockerfile.custom "${IMAGE_NATIVE_TAG}"
    ;;
  local)
    build_image Dockerfile.local "${IMAGE_LOCAL_TAG}"
    ;;
  images)
    build_image Dockerfile.custom "${IMAGE_NATIVE_TAG}"
    build_image Dockerfile.local  "${IMAGE_LOCAL_TAG}"
    ;;
  all)
    "${BUILD_DIR}/build-node-binaries.sh"
    "${BUILD_DIR}/build-runner-package.sh"
    build_image Dockerfile.custom "${IMAGE_NATIVE_TAG}"
    build_image Dockerfile.local  "${IMAGE_LOCAL_TAG}"
    log "Done. Images: ${IMAGE_NATIVE_TAG}, ${IMAGE_LOCAL_TAG}"
    ;;
  *)
    echo "Usage: $0 [all|node|package|images|native|local]" >&2
    exit 2
    ;;
esac
