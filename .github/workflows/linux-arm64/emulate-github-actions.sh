#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."


rm -rf github-actions-emulated
mkdir -p github-actions-emulated/{build,check}
echo '*' >github-actions-emulated/.gitignore

rm -f lincs-*.tar.gz
docker run \
  --rm -it \
  --volume "$PWD:/wd" --workdir /wd \
  python:3.13-slim bash -c """
set -o errexit

pip3 install build
python3 -m build --sdist --outdir github-actions-emulated/build

chown $(id -u):$(id -g) -R .
"""

(
  cp .github/workflows/linux-arm64/build.Dockerfile github-actions-emulated/build/Dockerfile
  cd github-actions-emulated/build
  docker buildx build --platform linux/arm64 --build-arg PYTHON_VERSION=3.8 --load .
  image=$(docker buildx build --platform linux/arm64 --build-arg PYTHON_VERSION=3.8 --load . --quiet)
  container=$(docker create --platform linux/arm64 $image)
  docker cp $container:/wd/dist .
  cp dist/*.whl ../check
)

(
  cp .github/workflows/linux-arm64/check.Dockerfile github-actions-emulated/check/Dockerfile
  cd github-actions-emulated/check
  docker buildx build --platform linux/arm64 --build-arg PYTHON_VERSION=3.8 --load .
  image=$(docker buildx build --platform linux/arm64 --build-arg PYTHON_VERSION=3.8 --load . --quiet)
  container=$(docker create --platform linux/arm64 $image)
  docker cp $container:/output.txt - | tar --extract --to-stdout
)
