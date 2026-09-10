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
# Optional 5th arg: HOSTCC for kbuild host tools (prefer linuxulator gcc on FreeBSD).
HOSTCC="${5:-$CLANG}"
export MAKE=gmake
export TARGET_TRIPLE="${TARGET_TRIPLE:-x86_64-linux-gnu}"

gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 HOSTCC="$HOSTCC" defconfig

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

gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 HOSTCC="$HOSTCC" olddefconfig

# olddefconfig may re-enable CONFIG_OBJTOOL=y (default on x86). Force off for
# FreeBSD host builds — objtool needs Linux asm headers we do not have.
"$BASH" "$SC" --file "$BUILD/.config" --disable OBJTOOL
"$BASH" "$SC" --file "$BUILD/.config" --disable STACK_VALIDATION
"$BASH" "$SC" --file "$BUILD/.config" --disable UNWINDER_ORC
"$BASH" "$SC" --file "$BUILD/.config" --enable UNWINDER_FRAME_POINTER
"$BASH" "$SC" --file "$BUILD/.config" --disable MODULE_SIG
"$BASH" "$SC" --file "$BUILD/.config" --disable MODULE_SIG_ALL
"$BASH" "$SC" --file "$BUILD/.config" --disable SYSTEM_TRUSTED_KEYRING
"$BASH" "$SC" --file "$BUILD/.config" --disable SYSTEM_REVOCATION_LIST
"$BASH" "$SC" --file "$BUILD/.config" --disable IMA
"$BASH" "$SC" --file "$BUILD/.config" --disable INTEGRITY
# Do NOT re-run olddefconfig after this or OBJTOOL/MODULE_SIG come back.
