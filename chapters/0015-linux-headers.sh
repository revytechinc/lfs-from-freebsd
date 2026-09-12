#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0015-linux-headers.sh — LFS §5.4 Linux API headers
# Uses the same kernel tarball as the FreeBSD-built product kernel (6.12.21),
# not a newer book pin, so glibc matches the shipped bzImage.
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0015}"

VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
# Prefer explicit version; fall back to any linux-*.tar.xz in vendor.
SRC="${LF_LINUX_TARBALL:-$VENDOR/linux-6.12.21.tar.xz}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"

echo "=== chapter ${LF_CHAPTER_ID}: Linux API headers from $(basename "$SRC") ==="
[ -f "$SRC" ] || {
	echo "missing $SRC" >&2
	exit 1
}

mkdir -p "$BUILD_ROOT" "$LFS/usr"
rm -rf "$BUILD_ROOT/linux-headers"
mkdir -p "$BUILD_ROOT/linux-headers"
tar -C "$BUILD_ROOT/linux-headers" --strip-components=1 -xf "$SRC"
cd "$BUILD_ROOT/linux-headers"

make mrproper
make -j"$JOBS" headers
find usr/include -type f ! -name '*.h' -delete
cp -a usr/include "$LFS/usr/"

[ -f "$LFS/usr/include/linux/kernel.h" ] || {
	echo "ERROR: headers not installed under $LFS/usr/include" >&2
	exit 1
}

rm -rf "$BUILD_ROOT/linux-headers"
mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
