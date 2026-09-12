#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0030-binutils-pass2.sh — LFS 12.3 §6.17 Binutils Pass 2
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0030}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: binutils-2.44 pass 2 ==="
[ -f "$VENDOR/binutils-2.44.tar.xz" ] || {
	echo "missing binutils tarball" >&2
	exit 1
}
[ -e "$LFS/usr/lib/libc.so.6" ] || [ -e "$LFS/lib/libc.so.6" ] || {
	echo "glibc required" >&2
	exit 1
}

mkdir -p "$BUILD_ROOT"
rm -rf "$BUILD_ROOT/binutils-2.44" "$BUILD_ROOT/binutils-pass2"
tar -C "$BUILD_ROOT" -xf "$VENDOR/binutils-2.44.tar.xz"
cd "$BUILD_ROOT/binutils-2.44"
sed '6031s/$add_dir//' -i ltmain.sh

mkdir -p "$BUILD_ROOT/binutils-pass2"
cd "$BUILD_ROOT/binutils-pass2"
../binutils-2.44/configure \
	--prefix=/usr \
	--build="$(../binutils-2.44/config.guess)" \
	--host="$LFS_TGT" \
	--disable-nls \
	--enable-shared \
	--enable-gprofng=no \
	--disable-werror \
	--enable-64-bit-bfd \
	--enable-new-dtags \
	--enable-default-hash-style=gnu

make -j"$JOBS"
make DESTDIR="$LFS" install
rm -f "$LFS/usr/lib/libbfd.a" "$LFS/usr/lib/libbfd.la" \
	"$LFS/usr/lib/libctf.a" "$LFS/usr/lib/libctf.la" \
	"$LFS/usr/lib/libctf-nobfd.a" "$LFS/usr/lib/libctf-nobfd.la" \
	"$LFS/usr/lib/libopcodes.a" "$LFS/usr/lib/libopcodes.la" \
	"$LFS/usr/lib/libsframe.a" "$LFS/usr/lib/libsframe.la"

rm -rf "$BUILD_ROOT/binutils-2.44" "$BUILD_ROOT/binutils-pass2"
mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
