#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# apply-kernel-config.sh — defconfig + fragment → .config
#
# WHAT: Start from x86_64 defconfig; enable options listed in
#       config/kernel/lfs-from-freebsd.config (CONFIG_FOO=y lines).
# WHY:  Keep the fragment human-readable; avoid shipping a 10k-line .config.
# HOST: FreeBSD during make kernel.
# OUT:  Writes $BUILD/.config

set -eu
SRC="$1"
BUILD="$2"
FRAG="$3"
CLANG="$4"
export MAKE=gmake
export TARGET_TRIPLE="${TARGET_TRIPLE:-x86_64-linux-gnu}"

gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 HOSTCC="$CLANG" CROSS_COMPILE="${TARGET_TRIPLE:-x86_64-linux-gnu}-" defconfig

# Prefer in-tree scripts/config when present (shebang is bash — invoke explicitly).
SC="$SRC/scripts/config"
if [ ! -f "$SC" ]; then
	echo "ERROR: missing $SC" >&2
	exit 1
fi
BASH="$(command -v bash || true)"
[ -n "$BASH" ] || { echo "ERROR: bash required to run scripts/config on FreeBSD" >&2; exit 1; }

while IFS= read -r line || [ -n "$line" ]; do
	case "$line" in
	''|\#*) continue ;;
	CONFIG_*=y)
		opt="${line%=y}"
		opt="${opt#CONFIG_}"
		"$BASH" "$SC" --file "$BUILD/.config" --enable "$opt"
		;;
	CONFIG_*=m)
		opt="${line%=m}"
		opt="${opt#CONFIG_}"
		"$BASH" "$SC" --file "$BUILD/.config" --module "$opt"
		;;
	CONFIG_*=n)
		opt="${line%=n}"
		opt="${opt#CONFIG_}"
		"$BASH" "$SC" --file "$BUILD/.config" --disable "$opt"
		;;
	esac
done < "$FRAG"

gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 HOSTCC="$CLANG" CROSS_COMPILE="${TARGET_TRIPLE:-x86_64-linux-gnu}-" olddefconfig
