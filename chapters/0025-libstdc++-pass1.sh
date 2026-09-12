#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0025-libstdc++-pass1.sh — LFS 12.3 §5.6 Libstdc++ from GCC-14.2.0
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0025}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: libstdc++ from gcc-14.2.0 ==="
[ -f "$VENDOR/gcc-14.2.0.tar.xz" ] || {
	echo "missing gcc tarball" >&2
	exit 1
}
[ -x "$LFS/tools/bin/${LFS_TGT}-g++" ] || {
	echo "gcc pass1 required" >&2
	exit 1
}
[ -e "$LFS/usr/lib/libc.so.6" ] || [ -e "$LFS/lib/libc.so.6" ] || {
	echo "glibc (0020) required" >&2
	exit 1
}

mkdir -p "$BUILD_ROOT"
rm -rf "$BUILD_ROOT/gcc-14.2.0" "$BUILD_ROOT/libstdc++-build"
tar -C "$BUILD_ROOT" -xf "$VENDOR/gcc-14.2.0.tar.xz"
mkdir -p "$BUILD_ROOT/libstdc++-build"
cd "$BUILD_ROOT/libstdc++-build"

../gcc-14.2.0/libstdc++-v3/configure \
	--host="$LFS_TGT" \
	--build="$(../gcc-14.2.0/config.guess)" \
	--prefix=/usr \
	--disable-multilib \
	--disable-nls \
	--disable-libstdcxx-pch \
	--with-gxx-include-dir="/tools/$LFS_TGT/include/c++/14.2.0"

make -j"$JOBS"
make DESTDIR="$LFS" install
rm -f "$LFS/usr/lib/libstdc++.la" \
	"$LFS/usr/lib/libstdc++exp.la" \
	"$LFS/usr/lib/libstdc++fs.la" \
	"$LFS/usr/lib/libsupc++.la"

rm -rf "$BUILD_ROOT/gcc-14.2.0" "$BUILD_ROOT/libstdc++-build"
mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
