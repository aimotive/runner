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
| 2. package | `build/build-runner-package.sh` | `build/.artifacts/actions-runner.tar.gz` (node baked into externals) |
| 3. images | `images/Dockerfile.custom`, `images/Dockerfile.local` | two runner images |

The Node versions are read automatically from `src/Misc/externals.sh`
(`NODE20_VERSION` / `NODE24_VERSION`) so they always match what this runner
expects.

## Usage

```bash
# Everything: node -> package -> both images
./build-runner-image.sh

# Individual steps
./build-runner-image.sh node       # build the custom node tarballs
./build-runner-image.sh package    # build the runner package (needs step 1)
./build-runner-image.sh native     # build images/Dockerfile.custom  (needs step 2)
./build-runner-image.sh local      # build images/Dockerfile.local   (needs step 2)
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

## The two images

| Image | Dockerfile | Base | Use |
| --- | --- | --- | --- |
| `gha-runner-native:custom` | `images/Dockerfile.custom` | `dotnet/runtime-deps:8.0-noble` | Same shape as GitHub's `images/Dockerfile` (container hooks + docker/buildx), but with the custom runner + node. For ARC / native runner deployments. |
| `gha-runner-local:custom` | `images/Dockerfile.local` | `myoung34/github-runner-base:latest` | Auto-registering self-hosted runner. Entrypoints lifted from `myoung34/github-runner`. |

Override tags with `IMAGE_NATIVE_TAG` / `IMAGE_LOCAL_TAG`.

## Requirements

- Docker (with buildx for multi-arch; `linux/amd64` by default).
- For the source node build: the `node20-ubuntu1804` repo at `../node20-ubuntu1804`
  (override with `NODE_REPO`).
- Network access (the package step downloads the .NET SDK and NuGet packages;
  the native image downloads container-hooks + docker + buildx).
