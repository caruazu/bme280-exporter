#!/usr/bin/env bash
# ESPECÍFICO — stack C: GCC, G++, GDB, CMake, Make, Valgrind,
#              cross-compilação aarch64 e empacotamento Debian.
# Executado no build da imagem, como root.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    gdb \
    cmake \
    make \
    valgrind \
    libc6-dev \
    build-essential \
    gcc-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    libc6-dev-arm64-cross \
    crossbuild-essential-arm64 \
    debhelper \
    fakeroot \
    lintian \
    devscripts

apt-get clean
rm -rf /var/lib/apt/lists/*

gcc --version
aarch64-linux-gnu-gcc --version
dpkg-buildpackage --version