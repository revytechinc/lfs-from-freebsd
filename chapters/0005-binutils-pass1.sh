#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0005-binutils-pass1.sh — LFS 12.3 §5.2 Binutils Pass 1
# Runs IN the Linux builder guest. Installs cross binutils into $LFS/tools.
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0005}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
SRC_TGZ="$VENDOR/binutils-2.44.tar.xz"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"

echo "=== chapter ${LF_CHAPTER_ID}: binutils-2.44 pass 1 (LFS_TGT=$LFS_TGT) ==="
[ -f "$SRC_TGZ" ] || {
	echo "missing $SRC_TGZ — fetch on FreeBSD host into vendor/" >&2
	exit 1
}

mkdir -p "$LFS/tools" "$BUILD_ROOT"
rm -rf "$BUILD_ROOT/binutils-2.44" "$BUILD_ROOT/binutils-pass1"
tar -C "$BUILD_ROOT" -xf "$SRC_TGZ"
mkdir -p "$BUILD_ROOT/binutils-pass1"
cd "$BUILD_ROOT/binutils-pass1"

../binutils-2.44/configure \
	--prefix="$LFS/tools" \
	--with-sysroot="$LFS" \
	--target="$LFS_TGT" \
	--disable-nls \
	--enable-gprofng=no \
	--disable-werror \
	--enable-new-dtags \
	--enable-default-hash-style=gnu

make -j"$JOBS"
make install

# Sanity: cross as exists
[ -x "$LFS/tools/bin/${LFS_TGT}-as" ] || {
	echo "ERROR: ${LFS_TGT}-as missing after install" >&2
	exit 1
}

rm -rf "$BUILD_ROOT/binutils-2.44" "$BUILD_ROOT/binutils-pass1"
mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
