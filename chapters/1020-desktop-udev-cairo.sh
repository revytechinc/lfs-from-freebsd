#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/1020-desktop-udev-cairo.sh — eudev + cairo + libinput.
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=1020}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: eudev + cairo + libinput ==="
[ -x "$LFS/tools/bin/${LFS_TGT}-gcc" ] || {
	echo "cross gcc required in \$LFS/tools" >&2
	exit 1
}

need_vendor() {
	[ -f "$VENDOR/$1" ] || {
		echo "missing pinned vendor/$1" >&2
		exit 1
	}
}
need_vendor eudev-3.2.14.tar.gz
need_vendor cairo-1.18.2.tar.xz
need_vendor libinput-1.27.1.tar.gz

export CC="${LFS_TGT}-gcc" CXX="${LFS_TGT}-g++"
export AR="${LFS_TGT}-ar" RANLIB="${LFS_TGT}-ranlib"
export CFLAGS="${CFLAGS:--g -O2} -Wno-implicit-function-declaration"
export CXXFLAGS="${CXXFLAGS:--g -O2}"

pkg_config_for_destdir() {
	export PKG_CONFIG_SYSROOT_DIR="$LFS"
	export PKG_CONFIG_LIBDIR="$LFS/usr/lib/pkgconfig:$LFS/usr/share/pkgconfig"
	export PKG_CONFIG_PATH=""
}
pkg_config_clear_sysroot() {
	unset PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR PKG_CONFIG_PATH
}

extract() {
	name="$1"
	tarball="$2"
	rm -rf "$BUILD_ROOT/$name"
	mkdir -p "$BUILD_ROOT/$name"
	tar -C "$BUILD_ROOT/$name" --strip-components=1 -xf "$VENDOR/$tarball"
}

write_meson_cross() {
	cross="$1"
	cat >"$cross" <<EOF
[binaries]
c = '${LFS_TGT}-gcc'
cpp = '${LFS_TGT}-g++'
ar = '${LFS_TGT}-ar'
strip = '${LFS_TGT}-strip'
pkg-config = 'pkgconf'
pkgconfig = 'pkgconf'
wayland-scanner = 'wayland-scanner'

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[properties]
sys_root = '$LFS'
pkg_config_libdir = '$LFS/usr/lib/pkgconfig:$LFS/usr/share/pkgconfig'

[built-in options]
c_link_args = ['-lm']
cpp_link_args = ['-lm']
EOF
}

build_meson() {
	name="$1"
	tarball="$2"
	shift 2
	echo "--- building $name (meson) ---"
	extract "$name" "$tarball"
	cross="$BUILD_ROOT/$name-cross.ini"
	write_meson_cross "$cross"
	cd "$BUILD_ROOT/$name"
	command -v meson >/dev/null 2>&1 || apk add --no-cache meson
	MESON_BIN="$(command -v meson)"
	case "$MESON_BIN" in
	"$LFS"/*)
		echo "ERROR: refusing DESTDIR meson ($MESON_BIN)" >&2
		exit 1
		;;
	esac
	command -v ninja >/dev/null 2>&1 || apk add --no-cache ninja
	pkg_config_clear_sysroot
	rm -rf build
	# shellcheck disable=SC2086
	"$MESON_BIN" setup build --prefix=/usr --buildtype=release \
		--cross-file="$cross" "$@"
	ninja -C build -j"$JOBS"
	DESTDIR="$LFS" ninja -C build install
	cd /
	rm -rf "$BUILD_ROOT/$name"
}

if [ -e "$LFS/usr/lib/libudev.so" ]; then
	echo "--- skip eudev (already installed) ---"
else
	echo "--- building eudev ---"
	extract eudev eudev-3.2.14.tar.gz
	cd "$BUILD_ROOT/eudev"
	command -v gperf >/dev/null 2>&1 || apk add --no-cache gperf
	# Some releases need autoreconf on Alpine.
	if [ ! -f configure ]; then
		command -v autoreconf >/dev/null 2>&1 || apk add --no-cache autoconf automake libtool
		autoreconf -fiv
	fi
	pkg_config_for_destdir
	./configure --prefix=/usr --host="$LFS_TGT" \
		--build="$(./config.guess 2>/dev/null || echo x86_64-pc-linux-musl)" \
		--disable-static --disable-manpages --disable-hwdb \
		--enable-kmod=no
	make -j"$JOBS"
	make DESTDIR="$LFS" install
	cd /
	rm -rf "$BUILD_ROOT/eudev"
fi

if [ -e "$LFS/usr/lib/libcairo.so" ]; then
	echo "--- skip cairo (already installed) ---"
else
	build_meson cairo cairo-1.18.2.tar.xz \
		-Dxlib=disabled -Dxcb=disabled -Dquartz=disabled \
		-Dtee=disabled -Dtests=disabled -Dgtk_doc=false \
		-Dspectre=disabled -Dsymbol-lookup=disabled \
		-Dpng=enabled -Dfontconfig=enabled -Dfreetype=enabled \
		-Dglib=disabled
fi

if [ -e "$LFS/usr/lib/libinput.so" ]; then
	echo "--- skip libinput (already installed) ---"
else
	build_meson libinput libinput-1.27.1.tar.gz \
		-Dlibwacom=false -Ddebug-gui=false -Dtests=false \
		-Ddocumentation=false -Dzshcompletiondir=no
fi

for f in \
	"$LFS/usr/lib/libudev.so" \
	"$LFS/usr/lib/libcairo.so" \
	"$LFS/usr/lib/libinput.so"
do
	[ -e "$f" ] || {
		echo "ERROR: missing $f" >&2
		exit 1
	}
done

mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
