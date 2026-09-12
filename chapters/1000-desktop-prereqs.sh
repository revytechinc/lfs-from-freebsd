#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/1000-desktop-prereqs.sh — first BLFS-style graphics stack batch
# into $LFS (cross from Alpine builder). Wayland + DRM + fonts foundations.
# Further prereqs (Mesa, libinput, PipeWire, …) land in later 10xx chapters
# or extend this script once pins exist.
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=1000}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: desktop prereqs (wayland/drm/fonts batch) ==="
[ -x "$LFS/tools/bin/${LFS_TGT}-gcc" ] || {
	echo "cross gcc required in \$LFS/tools" >&2
	exit 1
}

# Refuse until pinned tarballs exist (empty SHA in versions.env ⇒ no vendor file).
need_vendor() {
	[ -f "$VENDOR/$1" ] || {
		echo "missing pinned vendor/$1 — fetch after versions.env SHA is set" >&2
		exit 1
	}
}
need_vendor libpng-1.6.46.tar.xz
need_vendor freetype-2.13.3.tar.xz
need_vendor libxml2-2.13.6.tar.xz
need_vendor wayland-1.23.1.tar.xz
need_vendor wayland-protocols-1.41.tar.xz
need_vendor libdrm-2.4.124.tar.xz
need_vendor pixman-0.44.2.tar.gz

export CC="${LFS_TGT}-gcc" CXX="${LFS_TGT}-g++"
export AR="${LFS_TGT}-ar" RANLIB="${LFS_TGT}-ranlib"
export CFLAGS="${CFLAGS:--g -O2} -Wno-implicit-function-declaration"
export CXXFLAGS="${CXXFLAGS:--g -O2}"

# Autoconf packages: point pkg-config at DESTDIR. Meson cross builds must
# NOT inherit PKG_CONFIG_SYSROOT_DIR or native tools (wayland-scanner) vanish.
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
EOF
}

build_autoconf() {
	name="$1"
	tarball="$2"
	shift 2
	marker="$LFS/usr/lib/pkgconfig/${name}.pc"
	# libpng uses libpng16.pc; callers may pass a check path as last convention
	# via installed library instead:
	if [ -n "${CHECK_LIB:-}" ] && [ -e "$CHECK_LIB" ]; then
		echo "--- skip $name (already installed) ---"
		return 0
	fi
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

build_meson() {
	name="$1"
	tarball="$2"
	shift 2
	echo "--- building $name (meson) ---"
	extract "$name" "$tarball"
	cross="$BUILD_ROOT/$name-cross.ini"
	write_meson_cross "$cross"
	cd "$BUILD_ROOT/$name"
	# Host meson only — DESTDIR's /usr/bin/meson wrapper points at /usr/lib
	# (chroot paths) and cannot run on Alpine musl.
	command -v meson >/dev/null 2>&1 || apk add --no-cache meson
	MESON_BIN="$(command -v meson)"
	case "$MESON_BIN" in
	"$LFS"/*)
		echo "ERROR: refusing DESTDIR meson ($MESON_BIN); install host meson" >&2
		exit 1
		;;
	esac
	command -v ninja >/dev/null 2>&1 || apk add --no-cache ninja
	# Clear sysroot so native:true deps (wayland-scanner) use Alpine .pc files.
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

# --- libpng ---
if [ -e "$LFS/usr/lib/libpng16.so" ] || [ -e "$LFS/usr/lib/libpng.so" ]; then
	echo "--- skip libpng (already installed) ---"
else
	CHECK_LIB= build_autoconf libpng libpng-1.6.46.tar.xz --disable-static
fi

# --- freetype (no harfbuzz yet; rebuild later optional) ---
if [ -e "$LFS/usr/lib/libfreetype.so" ]; then
	echo "--- skip freetype (already installed) ---"
else
	echo "--- building freetype ---"
	extract freetype freetype-2.13.3.tar.xz
	cd "$BUILD_ROOT/freetype"
	pkg_config_for_destdir
	./configure --prefix=/usr --host="$LFS_TGT" \
		--build="$(./config.guess 2>/dev/null || echo x86_64-pc-linux-musl)" \
		--enable-shared --disable-static \
		--without-harfbuzz --without-brotli
	make -j"$JOBS"
	make DESTDIR="$LFS" install
	cd /
	rm -rf "$BUILD_ROOT/freetype"
fi

# --- libxml2 ---
if [ -e "$LFS/usr/lib/libxml2.so" ]; then
	echo "--- skip libxml2 (already installed) ---"
else
	echo "--- building libxml2 ---"
	extract libxml2 libxml2-2.13.6.tar.xz
	cd "$BUILD_ROOT/libxml2"
	pkg_config_for_destdir
	./configure --prefix=/usr --host="$LFS_TGT" \
		--build="$(./config.guess 2>/dev/null || echo x86_64-pc-linux-musl)" \
		--disable-static --with-history --with-icu=no \
		--without-python
	make -j"$JOBS"
	make DESTDIR="$LFS" install
	cd /
	rm -rf "$BUILD_ROOT/libxml2"
fi

# --- wayland (needs host wayland-scanner) ---
if [ -e "$LFS/usr/lib/libwayland-client.so" ]; then
	echo "--- skip wayland (already installed) ---"
else
	command -v wayland-scanner >/dev/null 2>&1 || apk add --no-cache wayland-dev
	build_meson wayland wayland-1.23.1.tar.xz \
		-Ddocumentation=false -Dtests=false -Ddtd_validation=false
fi

# --- wayland-protocols ---
if [ -d "$LFS/usr/share/wayland-protocols" ]; then
	echo "--- skip wayland-protocols (already installed) ---"
else
	build_meson wayland-protocols wayland-protocols-1.41.tar.xz \
		-Dtests=false
fi

# --- libdrm ---
if [ -e "$LFS/usr/lib/libdrm.so" ]; then
	echo "--- skip libdrm (already installed) ---"
else
	build_meson libdrm libdrm-2.4.124.tar.xz \
		-Dintel=disabled -Dradeon=disabled -Damdgpu=disabled \
		-Dnouveau=disabled -Dvmwgfx=enabled -Dudev=false \
		-Dvalgrind=disabled -Dtests=false
fi

# --- pixman ---
if [ -e "$LFS/usr/lib/libpixman-1.so" ]; then
	echo "--- skip pixman (already installed) ---"
else
	build_meson pixman pixman-0.44.2.tar.gz \
		-Dtests=disabled -Ddemos=disabled -Dgtk=disabled
fi

# Acceptance markers for this batch
for f in \
	"$LFS/usr/lib/libpng16.so" \
	"$LFS/usr/lib/libfreetype.so" \
	"$LFS/usr/lib/libxml2.so" \
	"$LFS/usr/lib/libwayland-client.so" \
	"$LFS/usr/lib/libdrm.so" \
	"$LFS/usr/lib/libpixman-1.so"
do
	[ -e "$f" ] || {
		echo "ERROR: missing $f after chapter ${LF_CHAPTER_ID}" >&2
		exit 1
	}
done
[ -d "$LFS/usr/share/wayland-protocols" ] || {
	echo "ERROR: wayland-protocols missing" >&2
	exit 1
}

mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
