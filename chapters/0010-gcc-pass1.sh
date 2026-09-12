#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0010-gcc-pass1.sh — LFS 12.3 §5.3 GCC Pass 1
# Runs IN the Linux builder guest. Cross GCC into $LFS/tools.
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0010}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: gcc-14.2.0 pass 1 (LFS_TGT=$LFS_TGT) ==="
for f in gcc-14.2.0.tar.xz mpfr-4.2.1.tar.xz gmp-6.3.0.tar.xz mpc-1.3.1.tar.gz; do
	[ -f "$VENDOR/$f" ] || {
		echo "missing $VENDOR/$f" >&2
		exit 1
	}
done
[ -x "$LFS/tools/bin/${LFS_TGT}-as" ] || {
	echo "binutils pass1 required first" >&2
	exit 1
}

mkdir -p "$BUILD_ROOT"
rm -rf "$BUILD_ROOT/gcc-14.2.0" "$BUILD_ROOT/gcc-pass1"
tar -C "$BUILD_ROOT" -xf "$VENDOR/gcc-14.2.0.tar.xz"
cd "$BUILD_ROOT/gcc-14.2.0"

tar -xf "$VENDOR/mpfr-4.2.1.tar.xz"
mv mpfr-4.2.1 mpfr
tar -xf "$VENDOR/gmp-6.3.0.tar.xz"
mv gmp-6.3.0 gmp
tar -xf "$VENDOR/mpc-1.3.1.tar.gz"
mv mpc-1.3.1 mpc

case "$(uname -m)" in
x86_64)
	sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
	;;
esac

mkdir -p "$BUILD_ROOT/gcc-pass1"
cd "$BUILD_ROOT/gcc-pass1"

../gcc-14.2.0/configure \
	--target="$LFS_TGT" \
	--prefix="$LFS/tools" \
	--with-glibc-version=2.41 \
	--with-sysroot="$LFS" \
	--with-newlib \
	--without-headers \
	--enable-default-pie \
	--enable-default-ssp \
	--disable-nls \
	--disable-shared \
	--disable-multilib \
	--disable-threads \
	--disable-libatomic \
	--disable-libgomp \
	--disable-libquadmath \
	--disable-libssp \
	--disable-libvtv \
	--disable-libstdcxx \
	--enable-languages=c,c++

make -j"$JOBS"
make install

cd "$BUILD_ROOT/gcc-14.2.0"
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
	"$(dirname "$("$LFS_TGT-gcc" -print-libgcc-file-name)")/include/limits.h"

[ -x "$LFS/tools/bin/${LFS_TGT}-gcc" ] || {
	echo "ERROR: ${LFS_TGT}-gcc missing" >&2
	exit 1
}

rm -rf "$BUILD_ROOT/gcc-14.2.0" "$BUILD_ROOT/gcc-pass1"
mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
