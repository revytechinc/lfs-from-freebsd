#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/1010-desktop-input-fonts.sh — xkb + fonts + evdev (pre-libinput).
# libinput needs udev/eudev — deferred until that lands.
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=1010}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: desktop input/fonts batch ==="
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
need_vendor libxkbcommon-1.8.1.tar.gz
need_vendor harfbuzz-10.2.0.tar.xz
need_vendor fontconfig-2.16.0.tar.xz
need_vendor libevdev-1.13.3.tar.xz
need_vendor mtdev-1.1.7.tar.bz2

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

build_autoconf() {
	name="$1"
	tarball="$2"
	shift 2
	echo "--- building $name ---"
	extract "$name" "$tarball"
	cd "$BUILD_ROOT/$name"
	pkg_config_for_destdir
	# shellcheck disable=SC2086
	./configure --prefix=/usr --host="$LFS_TGT" \
		--build="$(./config.guess 2>/dev/null || echo x86_64-pc-linux-musl)" \
		"$@"
	make -j"$JOBS"
	make DESTDIR="$LFS" install
	cd /
	rm -rf "$BUILD_ROOT/$name"
}

if [ -e "$LFS/usr/lib/libxkbcommon.so" ]; then
	echo "--- skip libxkbcommon (already installed) ---"
else
	command -v wayland-scanner >/dev/null 2>&1 || apk add --no-cache wayland-dev
	build_meson libxkbcommon libxkbcommon-1.8.1.tar.gz \
		-Denable-x11=false -Denable-docs=false -Denable-wayland=true
fi

	if [ -e "$LFS/usr/lib/libharfbuzz.so" ]; then
	echo "--- skip harfbuzz (already installed) ---"
else
	# Cross link needs explicit -lm (tanf/hypotf/sincosf).
	export LDFLAGS="${LDFLAGS:-} -lm"
	build_meson harfbuzz harfbuzz-10.2.0.tar.xz \
		-Dtests=disabled -Ddocs=disabled -Dintrospection=disabled \
		-Dglib=disabled -Dgobject=disabled -Dcairo=disabled \
		-Dfreetype=enabled
	unset LDFLAGS
fi

if [ -e "$LFS/usr/lib/libfontconfig.so" ]; then
	echo "--- skip fontconfig (already installed) ---"
else
	command -v gperf >/dev/null 2>&1 || apk add --no-cache gperf
	build_meson fontconfig fontconfig-2.16.0.tar.xz \
		-Ddoc=disabled -Dnls=disabled -Dtests=disabled \
		-Dtools=enabled -Dcache-build=disabled
fi

if [ -e "$LFS/usr/lib/libevdev.so" ]; then
	echo "--- skip libevdev (already installed) ---"
else
	build_meson libevdev libevdev-1.13.3.tar.xz \
		-Dtests=disabled -Ddocumentation=disabled
fi

if [ -e "$LFS/usr/lib/libmtdev.so" ]; then
	echo "--- skip mtdev (already installed) ---"
else
	build_autoconf mtdev mtdev-1.1.7.tar.bz2 --disable-static
fi

for f in \
	"$LFS/usr/lib/libxkbcommon.so" \
	"$LFS/usr/lib/libharfbuzz.so" \
	"$LFS/usr/lib/libfontconfig.so" \
	"$LFS/usr/lib/libevdev.so" \
	"$LFS/usr/lib/libmtdev.so"
do
	[ -e "$f" ] || {
		echo "ERROR: missing $f" >&2
		exit 1
	}
done

mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
