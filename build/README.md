# Custom runner build pipeline

Builds a GitHub Actions runner from this fork (`src/`) with **glibc-2.27
compatible Node.js 20 & 24** baked into its `externals/`, then produces two
container images from the same package.

## Why

GitHub actions now ship a Node 24 runtime. The official node binaries are linked
against `GLIBC_2.28`+, so running a JS action inside an **Ubuntu 18.04 job
container** fails with:

```
/__e/node24/bin/node: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.28' not found
```

The runner mounts its `externals/` into the job container, so the fix is to
replace the bundled `externals/node20` and `externals/node24` with a build made
*on* Ubuntu 18.04 (glibc 2.27) with a statically-linked libstdc++. Those
binaries come from the [`node20-ubuntu1804`](../../node20-ubuntu1804) repo.

## Pipeline

| Step | Script | Output |
| --- | --- | --- |
| 1. node | `build/build-node-binaries.sh` | `build/.artifacts/node/node20.tar.gz`, `node24.tar.gz` |
| 2. hooks | `build/build-hooks.sh` | `build/.artifacts/hooks/k8s-novolume/index.js` (custom fork) |
| 3. package | `build/build-runner-package.sh` | `build/.artifacts/actions-runner.tar.gz` (node baked into externals) |
| 4. images | `images/Dockerfile.custom`, `images/Dockerfile.local` | two runner images |

The **native** image (`Dockerfile.custom`) bakes in our
[`runner-container-hooks`](../../runner-container-hooks) fork as the
`k8s-novolume` hook (`/home/runner/k8s-novolume/index.js`) — this carries the
custom Kubernetes-mode features (work-volume PV reuse, node pinning, job
resource/usage reporting, reliable output copy-back). Point the runner at it
with `ACTIONS_RUNNER_CONTAINER_HOOKS=/home/runner/k8s-novolume/index.js`. The
stock upstream volume-based hook is still available at `/home/runner/k8s`.

The Node versions are read automatically from `src/Misc/externals.sh`
(`NODE20_VERSION` / `NODE24_VERSION`) so they always match what this runner
expects.

## Usage

```bash
# Everything: node -> hooks -> package -> both images
./build-runner-image.sh

# Individual steps
./build-runner-image.sh node       # build the custom node tarballs
./build-runner-image.sh hooks      # build the custom k8s-novolume hook
./build-runner-image.sh package    # build the runner package (needs step 1)
./build-runner-image.sh native     # build images/Dockerfile.custom  (needs steps 2+3)
./build-runner-image.sh local      # build images/Dockerfile.local   (needs step 3)
./build-runner-image.sh images     # build both images
```

### Skip the slow source build of Node

Building Node from source under emulation is slow. If you already have the
tarballs (e.g. from a `node20-ubuntu1804` GitHub Release), point at them:

```bash
NODE20_TARBALL=~/Downloads/node-v20.20.2-linux-x64.tar.gz \
NODE24_TARBALL=~/Downloads/node-v24.16.0-linux-x64.tar.gz \
./build-runner-image.sh
```

Likewise a prebuilt hook bundle can be reused instead of rebuilding the fork:

```bash
HOOKS_INDEX_JS=../runner-container-hooks/packages/k8s/dist/index.js \
./build-runner-image.sh
```

## The two images

| Image | Dockerfile | Base | Use |
| --- | --- | --- | --- |
| `gha-runner-native:custom` | `images/Dockerfile.custom` | `dotnet/runtime-deps:8.0-noble` | Same shape as GitHub's `images/Dockerfile` (docker/buildx + stock `k8s` hook + **custom `k8s-novolume` hook**), with the custom runner + node. For the Kubernetes self-hosted / ARC deployment. |
| `gha-runner-local:custom` | `images/Dockerfile.local` | `myoung34/github-runner-base:latest` | Auto-registering self-hosted runner. Entrypoints lifted from `myoung34/github-runner`. |

Override tags with `IMAGE_NATIVE_TAG` / `IMAGE_LOCAL_TAG`.

## Requirements

- Docker (with buildx for multi-arch; `linux/amd64` by default).
- For the source node build: the `node20-ubuntu1804` repo at `../node20-ubuntu1804`
  (override with `NODE_REPO`).
- For the custom hook build: the `runner-container-hooks` fork at
  `../runner-container-hooks` (override with `HOOKS_REPO`).
- Network access (the package step downloads the .NET SDK and NuGet packages;
  the hooks step runs `npm ci`; the native image downloads docker + buildx and
  the stock k8s hook).
