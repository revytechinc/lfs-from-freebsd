#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0200-lfs-base-packages.sh — first cut of LFS ch8-ish base tools
# (bash, coreutils, make, tar, …) cross-built into $LFS after toolchain pass2.
# Expand package list as pins land in vendor/.
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0200}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: LFS base packages (batch) ==="
# Always cross-build from the Alpine builder with $LFS/tools. The
# DESTDIR-installed $LFS/usr/bin/gcc is a glibc binary and cannot run on
# musl (missing /lib64/ld-linux-x86-64.so.2 on the builder host).
[ -x "$LFS/tools/bin/${LFS_TGT}-gcc" ] || {
	echo "cross gcc (${LFS_TGT}-gcc) required in \$LFS/tools before base packages" >&2
	exit 1
}

export CC="${LFS_TGT}-gcc" CXX="${LFS_TGT}-g++"
export AR="${LFS_TGT}-ar" RANLIB="${LFS_TGT}-ranlib"
# bash bundled gnutermcap (tparam.c) is pre-C99; GCC 14 errors on implicit decls.
export CFLAGS="${CFLAGS:--g -O2} -Wno-implicit-function-declaration"
export CXXFLAGS="${CXXFLAGS:--g -O2}"

build_one() {
	name="$1"
	tarball="$2"
	config_extra="${3:-}"
	make_jobs="${4:-$JOBS}"
	[ -f "$VENDOR/$tarball" ] || {
		echo "skip $name (missing $tarball)" >&2
		return 0
	}
	echo "--- building $name ---"
	rm -rf "$BUILD_ROOT/$name"
	mkdir -p "$BUILD_ROOT/$name"
	tar -C "$BUILD_ROOT/$name" --strip-components=1 -xf "$VENDOR/$tarball"
	cd "$BUILD_ROOT/$name"
	# shellcheck disable=SC2086
	./configure --prefix=/usr --host="$LFS_TGT" --build="$(./config.guess 2>/dev/null || echo x86_64-pc-linux-gnu)" $config_extra
	make -j"$make_jobs"
	make DESTDIR="$LFS" install
	cd /
	rm -rf "$BUILD_ROOT/$name"
}

# Cross-compile hints so bash configure/make do not try to run target tests.
export bash_cv_job_control_missing=present
export bash_cv_sys_named_pipes=present
export bash_cv_func_sigsetjmp=present
export bash_cv_getcwd_malloc=yes

# Minimal set to get a usable installed root shell / file utils.
# bash: -j1 avoids psize.sh / libtermcap races under parallel make.
build_one bash bash-5.2.37.tar.gz "--without-bash-malloc" 1
build_one coreutils coreutils-9.6.tar.xz "--enable-install-program=hostname"
build_one make make-4.4.1.tar.gz
build_one tar tar-1.35.tar.xz
build_one xz xz-5.6.4.tar.xz

# zlib's configure is not Autoconf — no --host; use CHOST for the cross prefix.
build_zlib() {
	tarball="zlib-1.3.1.tar.gz"
	[ -f "$VENDOR/$tarball" ] || {
		echo "skip zlib (missing $tarball)" >&2
		return 0
	}
	echo "--- building zlib ---"
	rm -rf "$BUILD_ROOT/zlib"
	mkdir -p "$BUILD_ROOT/zlib"
	tar -C "$BUILD_ROOT/zlib" --strip-components=1 -xf "$VENDOR/$tarball"
	cd "$BUILD_ROOT/zlib"
	CHOST="$LFS_TGT" ./configure --prefix=/usr
	make -j"$JOBS"
	make DESTDIR="$LFS" install
	cd /
	rm -rf "$BUILD_ROOT/zlib"
}
build_zlib

[ -x "$LFS/usr/bin/bash" ] || [ -x "$LFS/bin/bash" ] || {
	echo "ERROR: bash not installed into DESTDIR" >&2
	exit 1
}

mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
