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
# Host tools (relocs, etc.) often need GCC on FreeBSD; prefer ports gcc for HOSTCC.
HOSTCC="${LF_HOSTCC:-}"
if [ -z "$HOSTCC" ]; then
	for c in gcc14 gcc13 gcc12 gcc; do
		if command -v "$c" >/dev/null 2>&1; then
			HOSTCC="$c"
			break
		fi
	done
fi
[ -n "$HOSTCC" ] || HOSTCC="$CLANG"
JOBS="$(lf_jobs)"
export MAKE=gmake
# FreeBSD install(1) is not GNU — kbuild/objtool need ginstall from coreutils.
if command -v ginstall >/dev/null 2>&1; then
	export INSTALL=ginstall
elif [ -x /usr/local/bin/ginstall ]; then
	export INSTALL=/usr/local/bin/ginstall
else
	lf_die "ginstall missing — pkg install coreutils (GNU install required for kbuild)"
fi

lf_log "HOSTCC=$HOSTCC CLANG=$CLANG INSTALL=$INSTALL"

# Tools (objtool) expect <asm/types.h>; on x86 Linux this comes via the
# tools include path. Provide a tiny stub that pulls asm-generic.
mkdir -p "$SRC/tools/include/asm"
if [ ! -f "$SRC/tools/include/asm/types.h" ]; then
	cat > "$SRC/tools/include/asm/types.h" <<'EOF'
/* FreeBSD host stub for Linux tools/ builds — see docs/KERNEL-FROM-FREEBSD.md */
#ifndef _LF_TOOLS_ASM_TYPES_H
#define _LF_TOOLS_ASM_TYPES_H
#include <asm-generic/types.h>
#endif
EOF
fi

# LLVM=1 selects the Linux target from ARCH; do not set CROSS_COMPILE on FreeBSD
# (it confuses host-tool builds that must use FreeBSD headers).
"$LF_ROOT/scripts/apply-kernel-config.sh" "$SRC" "$BUILD" "$KCONFIG" "$CLANG"

# syncconfig during bzImage may flip OBJTOOL back on — force the line in .config
if [ -f "$BUILD/.config" ]; then
	sed -i.bak -e 's/^CONFIG_OBJTOOL=y$/# CONFIG_OBJTOOL is not set/' "$BUILD/.config"
fi

HOSTCFLAGS="-I$SRC/tools/include -I$SRC/include/uapi -I$SRC/tools/arch/x86/include -I$SRC/tools/arch/x86/include/uapi"

gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 \
	HOSTCC="$HOSTCC" \
	HOSTCFLAGS="$HOSTCFLAGS" \
	INSTALL="$INSTALL" \
	-j"$JOBS" bzImage modules

mkdir -p "$LF_OUT/linux/modules"
gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 \
	HOSTCC="$HOSTCC" \
	HOSTCFLAGS="$HOSTCFLAGS" \
	INSTALL="$INSTALL" \
	INSTALL_MOD_PATH="$LF_OUT/linux/modules" modules_install

# Install path for bzImage varies; prefer arch/x86/boot/bzImage.
BZIMAGE="$BUILD/arch/x86/boot/bzImage"
[ -f "$BZIMAGE" ] || lf_die "bzImage not found at $BZIMAGE"
cp -f "$BZIMAGE" "$LF_OUT/linux/bzImage"
cp -f "$BUILD/System.map" "$LF_OUT/linux/System.map" 2>/dev/null || true
cp -f "$BUILD/.config" "$LF_OUT/linux/config.actual"

# Export headers for OpenZFS builds (builder or local).
gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 \
	HOSTCC="$HOSTCC" \
	INSTALL="${INSTALL:-ginstall}" \
	INSTALL_HDR_PATH="$LF_OUT/linux/headers" headers_install

lf_log "=== kernel OK: $LF_OUT/linux/bzImage ==="
