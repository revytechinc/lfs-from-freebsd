#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0035-gcc-pass2.sh — LFS 12.3 §6.18 GCC Pass 2
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0035}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: gcc-14.2.0 pass 2 ==="
for f in gcc-14.2.0.tar.xz mpfr-4.2.1.tar.xz gmp-6.3.0.tar.xz mpc-1.3.1.tar.gz; do
	[ -f "$VENDOR/$f" ] || {
		echo "missing $VENDOR/$f" >&2
		exit 1
	}
done
[ -x "$LFS/usr/bin/as" ] || [ -x "$LFS/tools/bin/${LFS_TGT}-as" ] || {
	echo "binutils pass2 (or pass1) required" >&2
	exit 1
}

mkdir -p "$BUILD_ROOT"
rm -rf "$BUILD_ROOT/gcc-14.2.0" "$BUILD_ROOT/gcc-pass2"
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

sed '/thread_header =/s/@.*@/gthr-posix.h/' \
	-i libgcc/Makefile.in libstdc++-v3/include/Makefile.in

mkdir -p "$BUILD_ROOT/gcc-pass2"
cd "$BUILD_ROOT/gcc-pass2"

../gcc-14.2.0/configure \
	--build="$(../gcc-14.2.0/config.guess)" \
	--host="$LFS_TGT" \
	--target="$LFS_TGT" \
	LDFLAGS_FOR_TARGET="-L$PWD/$LFS_TGT/libgcc" \
	--prefix=/usr \
	--with-build-sysroot="$LFS" \
	--enable-default-pie \
	--enable-default-ssp \
	--disable-nls \
	--disable-multilib \
	--disable-libatomic \
	--disable-libgomp \
	--disable-libquadmath \
	--disable-libsanitizer \
	--disable-libssp \
	--disable-libvtv \
	--enable-languages=c,c++

make -j"$JOBS"
make DESTDIR="$LFS" install
ln -sfv gcc "$LFS/usr/bin/cc"

[ -x "$LFS/usr/bin/gcc" ] || {
	echo "ERROR: $LFS/usr/bin/gcc missing" >&2
	exit 1
}

rm -rf "$BUILD_ROOT/gcc-14.2.0" "$BUILD_ROOT/gcc-pass2"
mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
