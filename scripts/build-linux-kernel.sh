#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# build-linux-kernel.sh — PURE FreeBSD native build of Linux (LLVM target).
#
# WHAT: Extract vendor/linux-*.tar.xz, apply config fragment, build bzImage +
#       modules with FreeBSD clang/LLVM (LLVM=1). Host tools use FreeBSD HOSTCC.
# WHY:  Product claim — Linux kernel from FreeBSD. No linuxulator, no Linux
#       HOSTCC. See docs/ARCHITECTURE.md and docs/KERNEL-FROM-FREEBSD.md.
# HOST: FreeBSD only. Requires gmake, gsed, ginstall, bison, flex.
# OUT:  out/linux/bzImage, System.map, modules/, headers/
# DOCS: docs/KERNEL-FROM-FREEBSD.md

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

# shellcheck disable=SC1091
[ -f "$LF_OUT/toolchain/env.sh" ] && . "$LF_OUT/toolchain/env.sh"

lf_start_log kernel

lf_log "=== build-linux-kernel ${LINUX_VERSION} (PURE FreeBSD; no linuxulator) ==="

# Refuse linuxulator — that path is deliberately unsupported.
case "${LF_HOSTCC:-}${LF_HOSTCXX:-}${LF_HOSTLD:-}${LF_HOSTAR:-}" in
*/compat/linux/*)
	lf_die "linuxulator HOST* is forbidden. Use FreeBSD clang/gcc only (docs/KERNEL-FROM-FREEBSD.md)"
	;;
esac

SRC="$LF_OUT/linux/src"
BUILD="$LF_OUT/linux/build"
mkdir -p "$LF_OUT/linux"
rm -rf "$SRC"
mkdir -p "$SRC"
tar -xJf "$LF_VENDOR/$LINUX_TARBALL" -C "$SRC" --strip-components=1

# Neuter Linux-only host-tool traps that fight FreeBSD HOSTCC.
# Keep these patches minimal and documented in KERNEL-FROM-FREEBSD.md.
if [ -f "$SRC/scripts/Makefile.lib" ]; then
	sed -i.bak -e 's/^cmd_objtool = .*/cmd_objtool =/' "$SRC/scripts/Makefile.lib"
fi
if [ -f "$SRC/certs/Makefile" ]; then
	sed -i.bak \
		-e 's/^hostprogs := extract-cert$/hostprogs :=/' \
		-e 's|^      cmd_extract_certs  = .*|      cmd_extract_certs  = : > $@|' \
		-e 's| \$(obj)/extract-cert||g' \
		"$SRC/certs/Makefile"
fi

rm -rf "$BUILD"
mkdir -p "$BUILD"

KCONFIG="$LF_ROOT/config/kernel/lfs-from-freebsd.config"
[ -f "$KCONFIG" ] || lf_die "missing $KCONFIG"

CLANG="${LF_CLANG:-$(lf_clang)}"

# Host tools: FreeBSD-native only (clang or ports gcc). Never /compat/linux.
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
HOSTCXX="${LF_HOSTCXX:-}"
HOSTLD="${LF_HOSTLD:-}"
HOSTAR="${LF_HOSTAR:-}"

JOBS="$(lf_jobs)"
export MAKE=gmake
if command -v ginstall >/dev/null 2>&1; then
	export INSTALL=ginstall
elif [ -x /usr/local/bin/ginstall ]; then
	export INSTALL=/usr/local/bin/ginstall
else
	lf_die "ginstall missing — pkg install coreutils"
fi

# Host-tool stubs: Linux tools/ expect <asm/types.h> during some host compiles.
mkdir -p "$SRC/tools/include/asm"
if [ ! -f "$SRC/tools/include/asm/types.h" ]; then
	cat > "$SRC/tools/include/asm/types.h" <<'EOF'
/* FreeBSD-native stub for Linux tools/ — docs/KERNEL-FROM-FREEBSD.md */
#ifndef _LF_TOOLS_ASM_TYPES_H
#define _LF_TOOLS_ASM_TYPES_H
#include <asm-generic/types.h>
#endif
EOF
fi

lf_log "HOSTCC=$HOSTCC CLANG=$CLANG INSTALL=$INSTALL (FreeBSD-native)"

"$LF_ROOT/scripts/apply-kernel-config.sh" "$SRC" "$BUILD" "$KCONFIG" "$CLANG" "$HOSTCC"

if [ -f "$BUILD/.config" ]; then
	for opt in OBJTOOL STACK_VALIDATION MODULE_SIG MODULE_SIG_ALL \
		SYSTEM_TRUSTED_KEYRING SYSTEM_REVOCATION_LIST IMA INTEGRITY \
		SECURITY_SELINUX; do
		sed -i.bak -e "/^CONFIG_${opt}=/d" -e "/^# CONFIG_${opt} is not set/d" "$BUILD/.config"
		echo "# CONFIG_${opt} is not set" >> "$BUILD/.config"
	done
fi

# FreeBSD HOSTCC needs Linux tools/ uapi includes for some host programs.
HOSTCFLAGS="${LF_HOSTCFLAGS:--I$SRC/tools/include -I$SRC/include/uapi}"

# FreeBSD sed lacks GNU \| — voffset.h recipes hardcode `sed`.
if command -v gsed >/dev/null 2>&1; then
	GSED="$(command -v gsed)"
elif [ -x /usr/local/bin/gsed ]; then
	GSED=/usr/local/bin/gsed
else
	lf_die "gsed required (pkg install gsed)"
fi
LF_GSED_BIN="$LF_OUT/gnu-sed-bin"
mkdir -p "$LF_GSED_BIN"
ln -sfn "$GSED" "$LF_GSED_BIN/sed"
export PATH="$LF_GSED_BIN:$PATH"
SED="$GSED"
export SED

# FreeBSD clang may be newer than Linux 6.12 expects — keep as warnings.
KCFLAGS="${LF_KCFLAGS:--Wno-error=default-const-init-var-unsafe -Wno-error=default-const-init-field-unsafe -Wno-error=unterminated-string-initialization}"

gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 \
	HOSTCC="$HOSTCC" \
	${HOSTCXX:+HOSTCXX="$HOSTCXX"} \
	${HOSTLD:+HOSTLD="$HOSTLD"} \
	${HOSTAR:+HOSTAR="$HOSTAR"} \
	HOSTCFLAGS="$HOSTCFLAGS" \
	SED="$SED" \
	KCFLAGS="$KCFLAGS" \
	INSTALL="$INSTALL" \
	-j"$JOBS" bzImage modules

mkdir -p "$LF_OUT/linux/modules"
gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 \
	HOSTCC="$HOSTCC" \
	${HOSTCXX:+HOSTCXX="$HOSTCXX"} \
	${HOSTLD:+HOSTLD="$HOSTLD"} \
	${HOSTAR:+HOSTAR="$HOSTAR"} \
	HOSTCFLAGS="$HOSTCFLAGS" \
	SED="$SED" \
	KCFLAGS="$KCFLAGS" \
	INSTALL="$INSTALL" \
	INSTALL_MOD_PATH="$LF_OUT/linux/modules" modules_install

BZIMAGE="$BUILD/arch/x86/boot/bzImage"
[ -f "$BZIMAGE" ] || lf_die "bzImage not found at $BZIMAGE"
cp -f "$BZIMAGE" "$LF_OUT/linux/bzImage"
cp -f "$BUILD/System.map" "$LF_OUT/linux/System.map" 2>/dev/null || true
cp -f "$BUILD/.config" "$LF_OUT/linux/config.actual"

gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 \
	HOSTCC="$HOSTCC" \
	INSTALL="${INSTALL:-ginstall}" \
	INSTALL_HDR_PATH="$LF_OUT/linux/headers" headers_install

lf_log "=== kernel OK (pure FreeBSD): $LF_OUT/linux/bzImage ==="
