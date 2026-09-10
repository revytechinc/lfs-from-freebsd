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

# FreeBSD host: neuter host-tool traps that syncconfig keeps resurrecting.
# 1) certs/extract-cert links FreeBSD libcrypto into a linuxulator binary.
# 2) objtool (if still selected) fails on FreeBSD-built .o ("elf_begin: invalid command").
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
if [ ! -f "$KCONFIG" ]; then
	lf_die "missing $KCONFIG"
fi

CLANG="${LF_CLANG:-$(lf_clang)}"
# Host tools: prefer Linux ABI gcc under linuxulator so <asm/types.h> resolves.
HOSTCC="${LF_HOSTCC:-}"
if [ -z "$HOSTCC" ]; then
	if [ -x /compat/linux/usr/bin/gcc ]; then
		HOSTCC=/compat/linux/usr/bin/gcc
	else
		for c in gcc14 gcc13 gcc12 gcc; do
			if command -v "$c" >/dev/null 2>&1; then
				HOSTCC="$c"
				break
			fi
		done
	fi
fi
[ -n "$HOSTCC" ] || HOSTCC="$CLANG"
HOSTCXX="${LF_HOSTCXX:-}"
if [ -z "$HOSTCXX" ] && [ -x /compat/linux/usr/bin/g++ ]; then
	HOSTCXX=/compat/linux/usr/bin/g++
fi
HOSTLD="${LF_HOSTLD:-}"
HOSTAR="${LF_HOSTAR:-}"
if [ -z "$HOSTLD" ] && [ -x /compat/linux/usr/bin/ld ]; then
	HOSTLD=/compat/linux/usr/bin/ld
fi
if [ -z "$HOSTAR" ] && [ -x /compat/linux/usr/bin/ar ]; then
	HOSTAR=/compat/linux/usr/bin/ar
fi
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

# When using linuxulator host tools:
# - Stage Linux binutils + libelf.so for HOSTCC only (-B / -L), do NOT put them
#   on PATH and do NOT export LD_LIBRARY_PATH/LIBRARY_PATH (those make FreeBSD
#   clang load glibc → SIGSYS on vdso/realmode/random .o compiles).
# - Rocky ships libelf.so.1 but not libelf.so; without the unversioned symlink,
#   -lelf resolves FreeBSD /usr/lib/libelf.so and mixes libc.so.7 with glibc.
case "$HOSTCC" in
*/compat/linux/*)
	LF_LXBIN="$LF_OUT/linux-host-bin"
	LF_LXLIB="$LF_OUT/linux-host-lib"
	mkdir -p "$LF_LXBIN" "$LF_LXLIB"
	for t in ld as ar nm objcopy objdump strip ranlib; do
		if [ -x "/compat/linux/usr/bin/$t" ]; then
			ln -sfn "/compat/linux/usr/bin/$t" "$LF_LXBIN/$t"
		elif [ -x "/compat/linux/bin/$t" ]; then
			ln -sfn "/compat/linux/bin/$t" "$LF_LXBIN/$t"
		fi
	done
	if [ -e /compat/linux/usr/lib64/libelf.so.1 ]; then
		ln -sfn /compat/linux/usr/lib64/libelf.so.1 "$LF_LXLIB/libelf.so"
		ln -sfn /compat/linux/usr/lib64/libelf.so.1 "$LF_LXLIB/libelf.so.1"
	fi
	# Force host gcc's collect2 to this binutils dir without shadowing PATH.
	HOSTLDFLAGS="-L$LF_LXLIB -L/compat/linux/usr/lib64"
	HOSTCC="$HOSTCC -B$LF_LXBIN $HOSTLDFLAGS"
	[ -n "$HOSTCXX" ] && HOSTCXX="$HOSTCXX -B$LF_LXBIN $HOSTLDFLAGS"
	HOSTLD="$LF_LXBIN/ld"
	HOSTAR="$LF_LXBIN/ar"
	export HOSTLDFLAGS
	lf_log "linuxulator HOSTCC=$HOSTCC (no Linux LD_LIBRARY_PATH; FreeBSD clang safe)"
	;;
esac

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
"$LF_ROOT/scripts/apply-kernel-config.sh" "$SRC" "$BUILD" "$KCONFIG" "$CLANG" "$HOSTCC"

# syncconfig during bzImage may flip options back — force critical offs in .config
if [ -f "$BUILD/.config" ]; then
	for opt in OBJTOOL STACK_VALIDATION MODULE_SIG MODULE_SIG_ALL \
		SYSTEM_TRUSTED_KEYRING SYSTEM_REVOCATION_LIST IMA INTEGRITY; do
		sed -i.bak -e "/^CONFIG_${opt}=/d" -e "/^# CONFIG_${opt} is not set/d" "$BUILD/.config"
		echo "# CONFIG_${opt} is not set" >> "$BUILD/.config"
	done
fi

# Only add extra -I paths for FreeBSD-native HOSTCC; linuxulator gcc already
# has usable system <asm/*.h> and our tools/ -I paths break compiler.h.
HOSTCFLAGS=""
case "$HOSTCC" in
*/compat/linux*|*" -B"*)
	lf_log "linuxulator HOSTCC — using system Linux headers for host tools"
	;;
*)
	HOSTCFLAGS="-I$SRC/tools/include -I$SRC/include/uapi"
	;;
esac

# FreeBSD clang 21 treats new diagnostics as errors against Linux 6.12 sources.
KCFLAGS="${LF_KCFLAGS:--Wno-error=default-const-init-var-unsafe -Wno-error=default-const-init-field-unsafe -Wno-error=unterminated-string-initialization}"

gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 \
	HOSTCC="$HOSTCC" \
	${HOSTCXX:+HOSTCXX="$HOSTCXX"} \
	${HOSTLD:+HOSTLD="$HOSTLD"} \
	${HOSTAR:+HOSTAR="$HOSTAR"} \
	${HOSTCFLAGS:+HOSTCFLAGS="$HOSTCFLAGS"} \
	${HOSTLDFLAGS:+HOSTLDFLAGS="$HOSTLDFLAGS"} \
	KCFLAGS="$KCFLAGS" \
	INSTALL="$INSTALL" \
	-j"$JOBS" bzImage modules

mkdir -p "$LF_OUT/linux/modules"
gmake -C "$SRC" O="$BUILD" ARCH=x86_64 LLVM=1 LLVM_IAS=1 \
	HOSTCC="$HOSTCC" \
	${HOSTCXX:+HOSTCXX="$HOSTCXX"} \
	${HOSTLD:+HOSTLD="$HOSTLD"} \
	${HOSTAR:+HOSTAR="$HOSTAR"} \
	${HOSTCFLAGS:+HOSTCFLAGS="$HOSTCFLAGS"} \
	${HOSTLDFLAGS:+HOSTLDFLAGS="$HOSTLDFLAGS"} \
	KCFLAGS="$KCFLAGS" \
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
