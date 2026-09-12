#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0020-glibc.sh — LFS 12.3 §5.5 Glibc-2.41 (cross into $LFS)
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0020}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: glibc-2.41 ==="
[ -f "$VENDOR/glibc-2.41.tar.xz" ] || {
	echo "missing glibc tarball" >&2
	exit 1
}
[ -f "$VENDOR/glibc-2.41-fhs-1.patch" ] || {
	echo "missing glibc FHS patch" >&2
	exit 1
}
[ -f "$LFS/usr/include/linux/kernel.h" ] || {
	echo "linux headers (0015) required" >&2
	exit 1
}
[ -x "$LFS/tools/bin/${LFS_TGT}-gcc" ] || {
	echo "gcc pass1 (0010) required" >&2
	exit 1
}

mkdir -p "$LFS/lib" "$LFS/lib64" "$LFS/usr"
case "$(uname -m)" in
i?86) ln -sfv ld-linux.so.2 "$LFS/lib/ld-lsb.so.3" ;;
x86_64)
	ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64"
	ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
	;;
esac

mkdir -p "$BUILD_ROOT"
rm -rf "$BUILD_ROOT/glibc-2.41" "$BUILD_ROOT/glibc-build"
tar -C "$BUILD_ROOT" -xf "$VENDOR/glibc-2.41.tar.xz"
cd "$BUILD_ROOT/glibc-2.41"
patch -Np1 -i "$VENDOR/glibc-2.41-fhs-1.patch"

mkdir -p "$BUILD_ROOT/glibc-build"
cd "$BUILD_ROOT/glibc-build"
echo "rootsbindir=/usr/sbin" >configparms

../glibc-2.41/configure \
	--prefix=/usr \
	--host="$LFS_TGT" \
	--build="$(../glibc-2.41/scripts/config.guess)" \
	--enable-kernel=5.4 \
	--with-headers="$LFS/usr/include" \
	--disable-nscd \
	libc_cv_slibdir=/usr/lib

# Parallel make can flake on glibc; prefer JOBS but allow LF_GLIBC_JOBS=1.
make -j"${LF_GLIBC_JOBS:-$JOBS}"
make DESTDIR="$LFS" install
sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"

echo 'int main(){}' | "${LFS_TGT}-gcc" -xc -
readelf -l a.out | grep -q 'ld-linux' || {
	echo "ERROR: glibc toolchain sanity check failed" >&2
	readelf -l a.out || true
	exit 1
}
rm -f a.out

rm -rf "$BUILD_ROOT/glibc-2.41" "$BUILD_ROOT/glibc-build"
mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
