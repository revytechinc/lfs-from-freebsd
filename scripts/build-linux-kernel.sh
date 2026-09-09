#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# build-linux-kernel.sh — cross-build Linux on FreeBSD with LLVM.
#
# WHAT: Extract vendor/linux-*.tar.xz, apply config/kernel/lfs-from-freebsd.config,
#       build bzImage + modules with clang --target=x86_64-linux-gnu / LLVM=1.
# WHY:  Core “other way around” claim — Linux kernel from FreeBSD.
# HOST: FreeBSD (the CloudBSD build host). Requires prior `make toolchain` and `make fetch`.
# OUT:  out/linux/bzImage, out/linux/System.map, out/linux/modules/, headers tree
# DOCS: docs/ARCHITECTURE.md, docs/BUILD-HOST.md, docs/DESKTOP-PLASMA6.md (DRM opts)

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

# shellcheck disable=SC1091
[ -f "$LF_OUT/toolchain/env.sh" ] && . "$LF_OUT/toolchain/env.sh"

lf_start_log kernel

lf_log "=== build-linux-kernel ${LINUX_VERSION} ==="

SRC="$LF_OUT/linux/src"
BUILD="$LF_OUT/linux/build"
mkdir -p "$LF_OUT/linux"
rm -rf "$SRC"
mkdir -p "$SRC"
tar -xJf "$LF_VENDOR/$LINUX_TARBALL" -C "$SRC" --strip-components=1

rm -rf "$BUILD"
mkdir -p "$BUILD"

KCONFIG="$LF_ROOT/config/kernel/lfs-from-freebsd.config"
if [ ! -f "$KCONFIG" ]; then
	lf_die "missing $KCONFIG"
fi

CLANG="${LF_CLANG:-$(lf_clang)}"
JOBS="$(lf_jobs)"
export MAKE=gmake

"$LF_ROOT/scripts/apply-kernel-config.sh" "$SRC" "$BUILD" "$KCONFIG" "$CLANG"

gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 \
	HOSTCC="$CLANG" \
	CROSS_COMPILE="${TARGET_TRIPLE}-" \
	-j"$JOBS" bzImage modules

mkdir -p "$LF_OUT/linux/modules"
gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 \
	HOSTCC="$CLANG" \
	CROSS_COMPILE="${TARGET_TRIPLE}-" \
	INSTALL_MOD_PATH="$LF_OUT/linux/modules" modules_install

# Install path for bzImage varies; prefer arch/x86/boot/bzImage.
BZIMAGE="$BUILD/arch/x86/boot/bzImage"
[ -f "$BZIMAGE" ] || lf_die "bzImage not found at $BZIMAGE"
cp -f "$BZIMAGE" "$LF_OUT/linux/bzImage"
cp -f "$BUILD/System.map" "$LF_OUT/linux/System.map" 2>/dev/null || true
cp -f "$BUILD/.config" "$LF_OUT/linux/config.actual"

# Export headers for OpenZFS builds (builder or local).
gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 \
	HOSTCC="$CLANG" \
	CROSS_COMPILE="${TARGET_TRIPLE}-" \
	INSTALL_HDR_PATH="$LF_OUT/linux/headers" headers_install

lf_log "=== kernel OK: $LF_OUT/linux/bzImage ==="
