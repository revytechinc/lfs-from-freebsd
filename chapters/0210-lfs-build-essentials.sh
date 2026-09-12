#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0210-lfs-build-essentials.sh — next LFS ch8-ish packages needed
# before Qt/Plasma (ncurses, readline, pkgconf, openssl, …).
# Cross-built into $LFS from the Alpine builder using $LFS/tools.
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0210}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: LFS build essentials ==="
[ -x "$LFS/tools/bin/${LFS_TGT}-gcc" ] || {
	echo "cross gcc (${LFS_TGT}-gcc) required in \$LFS/tools" >&2
	exit 1
}

export CC="${LFS_TGT}-gcc" CXX="${LFS_TGT}-g++"
export AR="${LFS_TGT}-ar" RANLIB="${LFS_TGT}-ranlib"
export CFLAGS="${CFLAGS:--g -O2} -Wno-implicit-function-declaration"
export CXXFLAGS="${CXXFLAGS:--g -O2}"

extract() {
	name="$1"
	tarball="$2"
	[ -f "$VENDOR/$tarball" ] || {
		echo "missing $VENDOR/$tarball" >&2
		return 1
	}
	rm -rf "$BUILD_ROOT/$name"
	mkdir -p "$BUILD_ROOT/$name"
	tar -C "$BUILD_ROOT/$name" --strip-components=1 -xf "$VENDOR/$tarball"
}

build_autoconf() {
	name="$1"
	tarball="$2"
	config_extra="${3:-}"
	echo "--- building $name ---"
	extract "$name" "$tarball" || {
		echo "skip $name" >&2
		return 0
	}
	cd "$BUILD_ROOT/$name"
	# shellcheck disable=SC2086
	./configure --prefix=/usr --host="$LFS_TGT" \
		--build="$(./config.guess 2>/dev/null || echo x86_64-pc-linux-gnu)" \
		$config_extra
	make -j"$JOBS"
	make DESTDIR="$LFS" install
	cd /
	rm -rf "$BUILD_ROOT/$name"
}

build_ncurses() {
	echo "--- building ncurses ---"
	extract ncurses ncurses-6.5.tar.gz || {
		echo "skip ncurses" >&2
		return 0
	}
	cd "$BUILD_ROOT/ncurses"
	./configure --prefix=/usr --host="$LFS_TGT" \
		--build="$(./config.guess)" \
		--with-shared --without-normal --with-cxx-shared \
		--without-debug --without-ada --disable-stripping \
		--without-tests \
		--enable-widec --with-build-cc=gcc
	# Full `make` also builds the C++ demo, which fails to link under this
	# cross toolchain (_Unwind_* / libgcc). Build libs + progs + C++ .so only.
	make -j"$JOBS" libs
	make -C progs -j"$JOBS"
	make -C misc -j"$JOBS"
	make -C c++ -j"$JOBS" "../lib/libncurses++w.so.6.5"
	# Cross-built tic cannot run on Alpine musl — use the builder-host tic
	# to compile terminfo into DESTDIR.
	HOST_TIC="$(command -v tic || true)"
	[ -n "$HOST_TIC" ] || {
		echo "ERROR: need host tic to install ncurses terminfo when cross-compiling" >&2
		exit 1
	}
	make DESTDIR="$LFS" TIC_PATH="$HOST_TIC" install.libs install.includes \
		install.progs install.data install.pc-files
	make -C c++ DESTDIR="$LFS" install
	# Non-wide compatibility links (LFS).
	for lib in ncurses formw ncurses++ formw; do
		base=$(printf '%s' "$lib" | sed 's/w$//')
		if [ -e "$LFS/usr/lib/lib${lib}.so" ]; then
			echo "INPUT(-l${lib})" >"$LFS/usr/lib/lib${base}.so"
		fi
	done
	if [ -e "$LFS/usr/lib/libtinfow.so" ]; then
		echo "INPUT(-ltinfow)" >"$LFS/usr/lib/libtinfo.so"
	elif [ -e "$LFS/usr/lib/libtinfo.so" ]; then
		:
	elif [ -e "$LFS/usr/lib/libncursesw.so" ]; then
		echo "INPUT(-lncursesw)" >"$LFS/usr/lib/libtinfo.so"
	fi
	for lib in tic; do
		if [ -e "$LFS/usr/lib/lib${lib}w.so" ]; then
			ln -sf "lib${lib}w.so" "$LFS/usr/lib/lib${lib}.so" 2>/dev/null || true
		fi
	done
	# pkg-config names without w
	for pc in formw ncursesw ncurses++w; do
		src="$LFS/usr/lib/pkgconfig/${pc}.pc"
		dst="$LFS/usr/lib/pkgconfig/$(printf '%s' "$pc" | sed 's/w$//').pc"
		if [ -f "$src" ] && [ ! -e "$dst" ]; then
			sed 's/w$//; s/-lw$/-l/; s/w,/,/; s/w:/:/' "$src" >"$dst"
		fi
	done
	cd /
	rm -rf "$BUILD_ROOT/ncurses"
}

build_openssl() {
	echo "--- building openssl ---"
	extract openssl openssl-3.4.1.tar.gz || {
		echo "skip openssl" >&2
		return 0
	}
	cd "$BUILD_ROOT/openssl"
	# Configure's --cross-compile-prefix already adds the triple; do not also
	# export CC=${LFS_TGT}-gcc or Make looks for ${triple}-${triple}-gcc.
	(
		unset CC CXX AR RANLIB
		./Configure linux-x86_64 \
			--prefix=/usr \
			--openssldir=/etc/ssl \
			--libdir=lib \
			--cross-compile-prefix="${LFS_TGT}-" \
			shared zlib-dynamic
		make -j"$JOBS"
		make DESTDIR="$LFS" install_sw install_ssldirs
	)
	cd /
	rm -rf "$BUILD_ROOT/openssl"
}

# Order: m4 → ncurses → readline → pkgconf → libffi/expat → openssl → bison/flex
build_autoconf m4 m4-1.4.19.tar.xz
build_ncurses
build_autoconf readline readline-8.2.13.tar.gz "--with-curses --disable-static"
build_autoconf pkgconf pkgconf-2.3.0.tar.xz
# pkg-config compatibility symlink
if [ -x "$LFS/usr/bin/pkgconf" ] && [ ! -e "$LFS/usr/bin/pkg-config" ]; then
	ln -sf pkgconf "$LFS/usr/bin/pkg-config"
fi
build_autoconf libffi libffi-3.4.7.tar.gz "--disable-static --with-gcc-arch=x86-64"
build_autoconf expat expat-2.6.4.tar.xz "--disable-static"
build_openssl
build_autoconf bison bison-3.8.2.tar.xz "--disable-nls"
build_autoconf flex flex-2.6.4.tar.gz "--disable-nls ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes"

[ -f "$LFS/usr/lib/libncursesw.so" ] || [ -f "$LFS/usr/lib/libncurses.so" ] || {
	echo "ERROR: ncurses not installed" >&2
	exit 1
}
[ -x "$LFS/usr/bin/pkgconf" ] || [ -x "$LFS/usr/bin/pkg-config" ] || {
	echo "ERROR: pkgconf not installed" >&2
	exit 1
}

mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
