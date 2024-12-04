ARG PYTHON_VERSION=3.8


FROM --platform=$BUILDPLATFORM ubuntu:20.04 AS downloader

RUN set -x \
 && rm -f /etc/apt/apt.conf.d/docker-clean \
 && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' >/etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -x \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
      ca-certificates \
      wget

WORKDIR /download


FROM downloader AS download-lincs
ADD *.tar.gz .
RUN mv lincs-* lincs


FROM downloader AS download-boost

RUN set -x \
 && wget https://boostorg.jfrog.io/artifactory/main/release/1.82.0/source/boost_1_82_0.tar.gz \
 && tar xf boost_*.tar.gz \
 && rm boost_*.tar.gz \
 && mv boost_* boost


FROM downloader AS download-patchelf-amd64

RUN set -x \
 && wget https://github.com/NixOS/patchelf/releases/download/0.18.0/patchelf-0.18.0-x86_64.tar.gz \
 && mkdir patchelf \
 && cd patchelf \
 && tar xf ../patchelf-*.tar.gz \
 && cd .. \
 && rm patchelf-*.tar.gz

FROM downloader AS download-patchelf-arm64

RUN set -x \
 && wget https://github.com/NixOS/patchelf/releases/download/0.18.0/patchelf-0.18.0-aarch64.tar.gz \
 && mkdir patchelf \
 && cd patchelf \
 && tar xf ../patchelf-*.tar.gz \
 && cd .. \
 && rm patchelf-*.tar.gz

FROM download-patchelf-$TARGETARCH AS download-patchelf


FROM python:$PYTHON_VERSION AS build

WORKDIR /wd

RUN --mount=type=bind,from=download-patchelf,source=/download,target=/download \
    set -x \
 && cp /download/patchelf/bin/patchelf /usr/local/bin

RUN --mount=type=bind,from=download-boost,source=/download,target=/download,readwrite \
    set -x \
 && cp -r /download/boost/boost /usr/local/include

RUN pip3 install setuptools auditwheel build twine

RUN --mount=type=bind,from=download-lincs,source=/download,target=/download,readwrite \
    set -x \
 && python3 -m build --wheel --outdir local-dist /download/lincs


FROM build AS repair-amd64

RUN auditwheel repair --plat manylinux_2_35_x86_64 --strip local-dist/*.whl --wheel-dir dist

FROM build AS repair-arm64

RUN auditwheel repair --plat manylinux_2_35_aarch64 --strip local-dist/*.whl --wheel-dir dist

FROM repair-$TARGETARCH AS repair


FROM repair AS final

RUN twine check dist/*.whl
