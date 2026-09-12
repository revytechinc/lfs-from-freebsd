#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/1040-desktop-glib-dbus.sh — pcre2, glib, dbus, libepoxy (Qt6 path).
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=1040}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: pcre2 + glib + dbus + libepoxy ==="
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
need_vendor pcre2-10.45.tar.bz2
need_vendor glib-2.82.5.tar.xz
need_vendor dbus-1.16.2.tar.xz
need_vendor libepoxy-1.5.10.tar.gz

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
	CXX_VER="$("$CXX" -dumpversion)"
	cat >"$cross" <<EOF
[binaries]
c = '${LFS_TGT}-gcc'
cpp = '${LFS_TGT}-g++'
ar = '${LFS_TGT}-ar'
strip = '${LFS_TGT}-strip'
pkg-config = 'pkgconf'
pkgconfig = 'pkgconf'
wayland-scanner = 'wayland-scanner'
python = 'python3'

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[properties]
sys_root = '$LFS'
pkg_config_libdir = '$LFS/usr/lib/pkgconfig:$LFS/usr/share/pkgconfig'

[built-in options]
cpp_args = ['-O2', '-nostdinc++', '-isystem', '$LFS/usr/include/c++/$CXX_VER', '-isystem', '$LFS/usr/include/c++/$CXX_VER/$LFS_TGT', '-isystem', '$LFS/usr/include/c++/$CXX_VER/backward', '-isystem', '$LFS/usr/include']
c_link_args = ['-lm']
cpp_link_args = ['-lm', '-static-libstdc++', '-static-libgcc']
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

if [ -e "$LFS/usr/lib/libpcre2-8.so" ]; then
	echo "--- skip pcre2 (already installed) ---"
else
	echo "--- building pcre2 ---"
	extract pcre2 pcre2-10.45.tar.bz2
	cd "$BUILD_ROOT/pcre2"
	pkg_config_for_destdir
	./configure --prefix=/usr --host="$LFS_TGT" \
		--build="$(./config.guess 2>/dev/null || echo x86_64-pc-linux-musl)" \
		--enable-unicode-properties --enable-pcre2-16 --enable-pcre2-32 \
		--disable-static
	make -j"$JOBS"
	make DESTDIR="$LFS" install
	cd /
	rm -rf "$BUILD_ROOT/pcre2"
fi

if [ -e "$LFS/usr/lib/libglib-2.0.so" ]; then
	echo "--- skip glib (already installed) ---"
else
	echo "--- building glib (meson) ---"
	extract glib glib-2.82.5.tar.xz
	# Cross builds: gnulib frexp(l)/ldexpl subdirs need run tests or leave
	# frexpl_decl unset. Force known-good glibc results.
	sed -i \
		-e "s/subdir ('gl_cv_func_frexp_works')/gl_cv_func_frexp_works = true\n  gl_cv_func_frexp_broken_beyond_repair = false\n  gl_cv_func_frexp_decl = true/" \
		-e "s/subdir ('gl_cv_func_frexpl_works')/gl_cv_func_frexpl_works = true\n  gl_cv_func_frexpl_broken_beyond_repair = false\n  gl_cv_func_frexpl_decl = true/" \
		-e "s/subdir ('gl_cv_func_ldexpl_works')/gl_cv_func_ldexpl_works = true\n  gl_cv_func_ldexpl_decl = true/" \
		"$BUILD_ROOT/glib/glib/gnulib/meson.build"
	cross="$BUILD_ROOT/glib-cross.ini"
	write_meson_cross "$cross"
	cd "$BUILD_ROOT/glib"
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
	"$MESON_BIN" setup build --prefix=/usr --buildtype=release \
		--cross-file="$cross" \
		-Dselinux=disabled -Dlibmount=disabled -Dtests=false \
		-Dnls=disabled -Dintrospection=disabled -Dsysprof=disabled \
		-Dxattr=false
	# Force frexp(l) replacements off after configure if probes failed.
	ninja -C build -j"$JOBS"
	DESTDIR="$LFS" ninja -C build install
	cd /
	rm -rf "$BUILD_ROOT/glib"
fi

if [ -e "$LFS/usr/lib/libdbus-1.so" ]; then
	echo "--- skip dbus (already installed) ---"
else
	build_meson dbus dbus-1.16.2.tar.xz \
		-Dsystemd=disabled -Dselinux=disabled -Dx11_autolaunch=disabled \
		-Ddoxygen_docs=disabled -Dducktype_docs=disabled \
		-Dxml_docs=disabled -Dmodular_tests=disabled \
		-Duser_session=false -Dsystem_socket=/run/dbus/system_bus_socket
fi

if [ -e "$LFS/usr/lib/libepoxy.so" ]; then
	echo "--- skip libepoxy (already installed) ---"
else
	build_meson libepoxy libepoxy-1.5.10.tar.gz \
		-Dglx=no -Degl=yes -Dx11=false -Dtests=false
fi

for f in \
	"$LFS/usr/lib/libpcre2-8.so" \
	"$LFS/usr/lib/libglib-2.0.so" \
	"$LFS/usr/lib/libdbus-1.so" \
	"$LFS/usr/lib/libepoxy.so"
do
	[ -e "$f" ] || {
		echo "ERROR: missing $f" >&2
		exit 1
	}
done

mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
