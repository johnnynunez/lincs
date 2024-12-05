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


FROM downloader AS download-or-tools-amd64

RUN set -x \
 && wget https://github.com/google/or-tools/releases/download/v9.11/or-tools_amd64_ubuntu-20.04_cpp_v9.11.4210.tar.gz \
 && tar xf or-tools_*.tar.gz \
 && rm or-tools_*.tar.gz \
 && mv or-tools_* or-tools

FROM downloader AS download-or-tools-arm64
# @todo Build OR-Tools for ARM64 (or the subset of OR-Tools that we need)

RUN set -x \
 && wget https://github.com/google/or-tools/releases/download/v9.11/or-tools_amd64_ubuntu-20.04_cpp_v9.11.4210.tar.gz \
 && tar xf or-tools_*.tar.gz \
 && rm or-tools_*.tar.gz \
 && mv or-tools_* or-tools

FROM download-or-tools-$TARGETARCH AS download-or-tools


FROM downloader AS download-get-pip

RUN set -x \
 && wget https://bootstrap.pypa.io/get-pip.py


FROM ubuntu:20.04 AS build

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -x \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
      ccache \
      dirmngr \
      docker.io \
      g++ \
      git \
      gpg-agent \
      graphviz \
      jq \
      pandoc \
      python3-dev \
      python3-venv \
      software-properties-common \
      ssh \
      sudo

ARG PYTHON_VERSION
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=bind,from=download-get-pip,source=/download,target=/download \
    set -x \
 && add-apt-repository ppa:deadsnakes/ppa \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
      $(echo "python$PYTHON_VERSION-dev\npython$PYTHON_VERSION-distutils\npython$PYTHON_VERSION-venv" | grep -v python3.13-distutils) \
 && python$PYTHON_VERSION /download/get-pip.py

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -x \
 && apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/3bf863cc.pub \
 && add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/ /" \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
      cuda-cudart-dev-12-4 \
      cuda-nvcc-12-4
ENV PATH=$PATH:/usr/local/cuda-12.4/bin
# RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
#     --mount=type=cache,target=/var/lib/apt,sharing=locked \
#     set -x \
#  && apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/arm64/3bf863cc.pub \
#  && add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/arm64/ /" \
#  && apt-get update \
#  && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
#       cuda-cudart-dev-12-2 \
#       cuda-nvcc-12-2
# ENV PATH=$PATH:/usr/local/cuda-12.2/bin

RUN --mount=type=bind,from=download-patchelf,source=/download,target=/download \
    set -x \
 && cp /download/patchelf/bin/patchelf /usr/local/bin

RUN --mount=type=bind,from=download-boost,source=/download,target=/download,readwrite \
    set -x \
 && cp -r /download/boost/boost /usr/local/include

RUN --mount=type=bind,from=download-or-tools,source=/download,target=/download \
    set -x \
 && cp -r /download/or-tools/include/* /usr/local/include \
 && cp -r /download/or-tools/lib/libortools.so* /usr/local/lib \
 && ldconfig

RUN pip3 install setuptools auditwheel build twine Chrones

WORKDIR /wd

RUN --mount=type=bind,from=download-lincs,source=/download,target=/download,readwrite \
    set -x \
 && rm /download/lincs/lincs/liblincs/learning.cpp `# Do not waste time compiling tests in Qemu` \
 && LINCS_DEV_FORCE_NVCC=true LINCS_DEV_FORCE_CHRONES=true python3 -m build --wheel --outdir local-dist /download/lincs


FROM build AS repair-amd64

RUN auditwheel repair --plat manylinux_2_35_x86_64 --strip local-dist/*.whl --wheel-dir dist

FROM build AS repair-arm64

RUN auditwheel repair --plat manylinux_2_35_aarch64 --strip local-dist/*.whl --wheel-dir dist

FROM repair-$TARGETARCH AS repair


FROM repair AS final

RUN twine check dist/*.whl
