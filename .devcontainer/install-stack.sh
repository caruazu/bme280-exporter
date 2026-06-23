#!/usr/bin/env bash
# ESPECÍFICO — stack C: GCC, G++, GDB, CMake, Make, Valgrind
#              e empacotamento Debian.
# O container roda em arm64 (aarch64), portanto a compilação é
# NATIVA — não há toolchain de cross. O gcc nativo já gera aarch64.
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
    debhelper \
    fakeroot \
    lintian \
    devscripts

apt-get clean
rm -rf /var/lib/apt/lists/*

gcc --version
gcc -dumpmachine          # deve imprimir: aarch64-linux-gnu
dpkg-buildpackage --version
