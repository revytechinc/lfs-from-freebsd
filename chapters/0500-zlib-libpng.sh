#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0500-zlib-libpng.sh — first FreeBSD-cross userspace compile batch.
#
# WHAT: zlib + libpng into $LFS using $LFS_TGT-gcc wrappers (clang+sysroot).
# WHY:  Prove real package builds on FreeBSD without Alpine/linuxulator.
# HOST: FreeBSD via scripts/run-chapter-freebsd.sh (path of record).
# DOCS: docs/FREEBSD-CROSS-USERSPACE.md
set -eu
: "${LFS:?LFS root DESTDIR must be set (run via scripts/run-chapter-freebsd.sh)}"
# Chapter id comes from this script's filename only (runner may export the same).
_base=$(basename -- "$0" .sh)
LF_CHAPTER_ID="${_base%%-*}"
printf '%s' "$LF_CHAPTER_ID" | grep -Eq '^[0-9][0-9A-Za-z._-]*$' || {
	echo "ERROR: script filename must start with a numeric prefix (e.g. 0500-name.sh); run via scripts/run-chapter-freebsd.sh" >&2
	exit 1
}
case "$LF_CHAPTER_ID" in
*..*)
	echo "ERROR: LF_CHAPTER_ID must not contain .." >&2
	exit 1
	;;
esac

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:?LF_VENDOR must be set (run via scripts/run-chapter-freebsd.sh)}"
# Default under out/ — runner sets LF_BUILD_ROOT; refuse world-writable /var/tmp defaults.
BUILD_ROOT="${LF_BUILD_ROOT:?LF_BUILD_ROOT must be set (run via run-chapter-freebsd.sh)}"
JOBS="${LF_JOBS:-2}"
LFS_OUT_PREFIX="${LF_OUT:?LF_OUT must be set (run via scripts/run-chapter-freebsd.sh)}"

# Resolve LFS / BUILD_ROOT; refuse symlinks that escape $LF_OUT.
command -v realpath >/dev/null 2>&1 || {
	echo "ERROR: realpath required (FreeBSD base includes /usr/bin/realpath)" >&2
	exit 1
}
LFS="$(realpath -q "$LFS" 2>/dev/null || true)"
BUILD_ROOT="$(realpath -q "$BUILD_ROOT" 2>/dev/null || true)"
LFS_OUT_PREFIX="$(realpath -q "$LFS_OUT_PREFIX" 2>/dev/null || true)"
[ -n "$LFS" ] && [ -n "$BUILD_ROOT" ] && [ -n "$LFS_OUT_PREFIX" ] || {
	echo "ERROR: cannot resolve LFS/LF_BUILD_ROOT/LF_OUT; run via scripts/run-chapter-freebsd.sh" >&2
	exit 1
}
case "$LFS" in
"$LFS_OUT_PREFIX"|"$LFS_OUT_PREFIX"/*) ;;
*)
	echo "ERROR: LFS must resolve under $LFS_OUT_PREFIX (got $LFS)" >&2
	exit 1
	;;
esac
case "$BUILD_ROOT" in
"$LFS_OUT_PREFIX"|"$LFS_OUT_PREFIX"/*) ;;
*)
	echo "ERROR: LF_BUILD_ROOT must resolve under $LFS_OUT_PREFIX (got $BUILD_ROOT)" >&2
	exit 1
	;;
esac

# shellcheck disable=SC1091
. "${LF_ROOT:?}/versions.env"
ZLIB_TB="${ZLIB_TARBALL:-zlib-1.3.1.tar.gz}"
LIBPNG_TB="${LIBPNG_TARBALL:-libpng-1.6.46.tar.xz}"
ZLIB_EXPECT="${ZLIB_SHA256:?ZLIB_SHA256 must be set in versions.env}"
LIBPNG_EXPECT="${LIBPNG_SHA256:?LIBPNG_SHA256 must be set in versions.env}"

sha_of() {
	if command -v sha256 >/dev/null 2>&1; then
		sha256 -q "$1"
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		echo "ERROR: no sha256 tool found (install sha256 or coreutils for sha256sum)" >&2
		exit 1
	fi
}

echo "=== chapter ${LF_CHAPTER_ID}: zlib + libpng (FreeBSD cross) ==="
# Require FreeBSD clang wrappers under $LFS/tools (runner installs them).
[ -x "$LFS/tools/bin/${LFS_TGT}-gcc" ] || {
	echo "ERROR: missing $LFS/tools/bin/${LFS_TGT}-gcc — run gmake wrappers / run-chapter-freebsd.sh" >&2
	exit 1
}

need_vendor() {
	_tb="$1"
	_exp="$2"
	[ -f "$VENDOR/$_tb" ] || {
		echo "missing vendor/$_tb — gmake fetch after versions.env pin" >&2
		exit 1
	}
	_got="$(sha_of "$VENDOR/$_tb")"
	[ "$_got" = "$_exp" ] || {
		echo "ERROR: SHA256 mismatch for vendor/$_tb (expected $_exp got $_got) — remove vendor/$_tb and re-run gmake fetch" >&2
		exit 1
	}
}
need_vendor "$ZLIB_TB" "$ZLIB_EXPECT"
need_vendor "$LIBPNG_TB" "$LIBPNG_EXPECT"

export PATH="$LFS/tools/bin:${PATH:-}"
export CC="${LFS_TGT}-gcc"
export AR="${LFS_TGT}-ar"
export RANLIB="${LFS_TGT}-ranlib"
# Fixed flags only — do not inherit untrusted CFLAGS/CPPFLAGS/LDFLAGS from the environment.
export CFLAGS="-O2"
export CPPFLAGS="-I$LFS/usr/include"
export LDFLAGS="-L$LFS/usr/lib"
export PKG_CONFIG_SYSROOT_DIR="$LFS"
export PKG_CONFIG_LIBDIR="$LFS/usr/lib/pkgconfig:$LFS/usr/share/pkgconfig"
export PKG_CONFIG_PATH=""

extract() {
	name="$1"
	tarball="$2"
	rm -rf "$BUILD_ROOT/$name"
	mkdir -p "$BUILD_ROOT/$name"
	tar -C "$BUILD_ROOT/$name" --strip-components=1 -xf "$VENDOR/$tarball"
}

# --- zlib (not Autoconf; CHOST selects the cross prefix) ---
if [ -s "$LFS/usr/lib/libz.so" ] && [ -f "$LFS/usr/include/zlib.h" ]; then
	echo "--- skip zlib (already installed) ---"
else
	echo "--- building zlib ---"
	extract zlib "$ZLIB_TB"
	cd "$BUILD_ROOT/zlib"
	# zlib shared-lib probe fails if CC and/or CFLAGS are set; use CHOST only.
	CFLAGS_SAVE="${CFLAGS:-}"
	CC_SAVE="${CC:-}"
	unset CFLAGS CC
	CHOST="$LFS_TGT" ./configure --prefix=/usr
	CC="$CC_SAVE"
	CFLAGS="$CFLAGS_SAVE"
	export CC CFLAGS
	gmake -j"$JOBS"
	gmake DESTDIR="$LFS" install
	cd /
	[ -s "$LFS/usr/lib/libz.so" ] || {
		echo "ERROR: zlib did not install shared libz.so; inspect $BUILD_ROOT/zlib" >&2
		exit 1
	}
	rm -rf "$BUILD_ROOT/zlib"
fi

# --- libpng ---
if [ -s "$LFS/usr/lib/libpng16.so" ] && [ -f "$LFS/usr/include/png.h" ]; then
	echo "--- skip libpng (already installed) ---"
else
	echo "--- building libpng ---"
	extract libpng "$LIBPNG_TB"
	cd "$BUILD_ROOT/libpng"
	# FreeBSD host as build triple; Linux target as host.
	build_trip="$(uname -m)-unknown-freebsd"
	./configure --prefix=/usr \
		--host="$LFS_TGT" \
		--build="$build_trip" \
		--disable-static
	gmake -j"$JOBS"
	gmake DESTDIR="$LFS" install
	cd /
	[ -s "$LFS/usr/lib/libpng16.so" ] && [ -f "$LFS/usr/include/png.h" ] || {
		echo "ERROR: libpng did not install libpng16.so + png.h; inspect $BUILD_ROOT/libpng/config.log if present" >&2
		exit 1
	}
	rm -rf "$BUILD_ROOT/libpng"
fi

# Smoke: link a tiny Linux ELF that uses libz + libpng (headers from DESTDIR + sysroot).
PROBE_C="$BUILD_ROOT/lf-zprobe.c"
PROBE_OUT="$LFS/usr/bin/lf-zprobe"
mkdir -p "$BUILD_ROOT" "$LFS/usr/bin"
printf '%s\n' \
	'#include <zlib.h>' \
	'#include <png.h>' \
	'#include <stdio.h>' \
	'int main(void){printf("zlib %s png %s\\n", zlibVersion(), PNG_LIBPNG_VER_STRING); return 0;}' \
	>"$PROBE_C"
# Fixed flags only — do not expand untrusted CPPFLAGS/CFLAGS/LDFLAGS from the environment.
"$CC" "-I$LFS/usr/include" -O2 "-L$LFS/usr/lib" "$PROBE_C" -lz -lpng16 -o "$PROBE_OUT"
# Prove NEEDED libs (not file(1) grepping an injected -dynamic-linker).
command -v llvm-readobj >/dev/null 2>&1 || {
	echo "ERROR: llvm-readobj required to verify lf-zprobe (pkg install llvm)" >&2
	exit 1
}
_needed="$(llvm-readobj --needed-libs "$PROBE_OUT")" || {
	echo "ERROR: llvm-readobj --needed-libs failed for $PROBE_OUT" >&2
	exit 1
}
printf '%s\n' "$_needed" | grep -Eq 'libz\.so' || {
	echo "ERROR: lf-zprobe missing NEEDED libz.so — check $LFS/usr/lib/libz.so and rebuild chapter" >&2
	exit 1
}
printf '%s\n' "$_needed" | grep -Eq 'libpng' || {
	echo "ERROR: lf-zprobe missing NEEDED libpng — check $LFS/usr/lib/libpng16.so and rebuild chapter" >&2
	exit 1
}
printf '%s\n' "$_needed" | grep -Eq 'libc\.so' || {
	echo "ERROR: lf-zprobe missing NEEDED libc.so — re-run gmake sysroot / wrappers" >&2
	exit 1
}
# INTERP is set by the FreeBSD clang wrappers; treat as wrapper-used, not musl proof.
_prog="$(llvm-readobj --program-headers "$PROBE_OUT")" || {
	echo "ERROR: llvm-readobj --program-headers failed for $PROBE_OUT — inspect binary or re-run gmake wrappers" >&2
	exit 1
}
printf '%s\n' "$_prog" | grep -Fq "Name: /lib/ld-musl-x86_64.so.1" || {
	echo "ERROR: lf-zprobe INTERP must be /lib/ld-musl-x86_64.so.1 — re-run gmake wrappers" >&2
	exit 1
}

: "${LF_CHAPTER_STATE:?LF_CHAPTER_STATE must be set (run via scripts/run-chapter-freebsd.sh)}"
LF_CHAPTER_STATE="$(realpath -q "$LF_CHAPTER_STATE" 2>/dev/null || true)"
[ -n "$LF_CHAPTER_STATE" ] || {
	echo "ERROR: cannot resolve LF_CHAPTER_STATE; run via scripts/run-chapter-freebsd.sh" >&2
	exit 1
}
case "$LF_CHAPTER_STATE" in
"$LFS_OUT_PREFIX"|"$LFS_OUT_PREFIX"/*) ;;
*)
	echo "ERROR: LF_CHAPTER_STATE must resolve under $LFS_OUT_PREFIX; run via run-chapter-freebsd.sh" >&2
	exit 1
	;;
esac
mkdir -p "$LF_CHAPTER_STATE"
touch "${LF_CHAPTER_STATE}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
