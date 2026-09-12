#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/1030-mesa.sh — Mesa (Wayland EGL) for bhyve virtio-gpu + VMware svga.
# LLVM disabled for now (softpipe + virgl + svga).
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=1030}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: Mesa + libglvnd ==="
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
need_vendor libglvnd-1.7.0.tar.gz
need_vendor mesa-24.3.4.tar.xz

export CC="${LFS_TGT}-gcc" CXX="${LFS_TGT}-g++"
export AR="${LFS_TGT}-ar" RANLIB="${LFS_TGT}-ranlib"
export CFLAGS="${CFLAGS:--g -O2} -Wno-implicit-function-declaration"
export CXXFLAGS="${CXXFLAGS:--g -O2}"

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
	# Single-line arrays — multi-line heredoc arrays confused meson earlier.
	# tools g++ is --disable-threads; use gcc-pass2 C++ headers from $LFS/usr.
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

# Host python Mako + PyYAML required by Mesa's codegen.
python3 -c 'import mako' 2>/dev/null || apk add --no-cache py3-mako
python3 -c 'import yaml' 2>/dev/null || apk add --no-cache py3-yaml
command -v wayland-scanner >/dev/null 2>&1 || apk add --no-cache wayland-dev

if [ -e "$LFS/usr/lib/libGLdispatch.so" ]; then
	echo "--- skip libglvnd (already installed) ---"
else
	build_meson libglvnd libglvnd-1.7.0.tar.gz \
		-Dx11=disabled -Dglx=disabled -Degl=true -Dgles1=true -Dgles2=true \
		-Dheaders=true -Dhgl=false
fi

if ls "$LFS/usr/lib"/dri/*_dri.so >/dev/null 2>&1; then
	echo "--- skip mesa (already installed) ---"
else
	# softpipe (no LLVM); virgl for bhyve/virtio-gpu; svga for VMware.
	build_meson mesa mesa-24.3.4.tar.xz \
		-Dplatforms=wayland \
		-Dgallium-drivers=softpipe,virgl,svga \
		-Dvulkan-drivers= \
		-Dglx=disabled \
		-Dllvm=disabled \
		-Dgallium-vdpau=disabled \
		-Dgallium-va=disabled \
		-Dgallium-xa=disabled \
		-Dmicrosoft-clc=disabled \
		-Dvalgrind=disabled \
		-Dlibunwind=disabled \
		-Dlmsensors=disabled \
		-Dbuild-tests=false \
		-Dglvnd=enabled \
		-Degl=enabled \
		-Dgles1=disabled \
		-Dgles2=enabled \
		-Dgbm=enabled \
		-Dvideo-codecs=[]
fi

# Smoke: EGL + gallium DRI (Mesa 24+ ships one libgallium-*.so; dri/*.so are symlinks).
[ -e "$LFS/usr/lib/libEGL.so" ] || [ -e "$LFS/usr/lib/libEGL.so.1" ] || {
	echo "ERROR: libEGL missing" >&2
	exit 1
}
GALLIUM=
for g in "$LFS/usr/lib"/libgallium-*.so; do
	[ -e "$g" ] || continue
	GALLIUM="$g"
	break
done
[ -n "$GALLIUM" ] || {
	echo "ERROR: libgallium-*.so missing" >&2
	exit 1
}
# Ensure classic dri loader names exist (install sometimes skips symlink step).
mkdir -p "$LFS/usr/lib/dri"
base="$(basename "$GALLIUM")"
for d in swrast kms_swrast virtio_gpu vmwgfx; do
	[ -e "$LFS/usr/lib/dri/${d}_dri.so" ] || ln -sfn "../$base" "$LFS/usr/lib/dri/${d}_dri.so"
done
ls "$LFS/usr/lib"/dri/*_dri.so >/dev/null 2>&1 || {
	echo "ERROR: no DRI drivers installed" >&2
	exit 1
}

mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
