#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/1450-open-vm-tools.sh — Open VM Tools for VMware guests (installed).
#
# WHAT: Cross-build/install open-vm-tools into $LFS for Workstation/Fusion/ESXi.
# WHY:  Operator acceptance includes mouse/time sync inside a VMware VM.
# HOST: FreeBSD via scripts/run-chapter-freebsd.sh (or historical Alpine chapter).
# DOCS: docs/DESKTOP-PLASMA6.md
set -eu

: "${LFS:?LFS must be set (run via scripts/run-chapter-freebsd.sh)}"
: "${LF_ROOT:?set LF_ROOT to lfs-from-freebsd tree}"
: "${LF_VENDOR:=$LF_ROOT/vendor}"
_base=$(basename -- "$0" .sh)
LF_CHAPTER_ID="${_base%%-*}"
LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"

# shellcheck disable=SC1091
. "$LF_ROOT/versions.env"

echo "=== chapter ${LF_CHAPTER_ID}: open-vm-tools ${OPEN_VM_TOOLS_VERSION:-unset} ==="

if [ -z "${OPEN_VM_TOOLS_VERSION:-}" ] || [ -z "${OPEN_VM_TOOLS_TARBALL:-}" ]; then
	echo "ERROR: pin OPEN_VM_TOOLS_* in versions.env before this chapter runs" >&2
	exit 1
fi
[ -n "${OPEN_VM_TOOLS_SHA256:-}" ] || {
	echo "ERROR: OPEN_VM_TOOLS_SHA256 empty — pin SHA in versions.env before fetch/build" >&2
	exit 1
}

SRC_TAR="$LF_VENDOR/$OPEN_VM_TOOLS_TARBALL"
[ -f "$SRC_TAR" ] || {
	echo "ERROR: missing $SRC_TAR — run gmake fetch after pinning" >&2
	exit 1
}
if command -v sha256 >/dev/null 2>&1; then
	_got=$(sha256 -q "$SRC_TAR")
elif command -v sha256sum >/dev/null 2>&1; then
	_got=$(sha256sum "$SRC_TAR" | awk '{print $1}')
else
	echo "ERROR: no sha256 tool found" >&2
	exit 1
fi
[ "$_got" = "$OPEN_VM_TOOLS_SHA256" ] || {
	echo "ERROR: SHA256 mismatch for $SRC_TAR — remove and re-fetch" >&2
	exit 1
}

[ -x "$LFS/tools/bin/${LFS_TGT}-gcc" ] || [ -x "$(command -v "${LFS_TGT}-gcc" || true)" ] || {
	echo "ERROR: cross ${LFS_TGT}-gcc required (gmake wrappers)" >&2
	exit 1
}
export PATH="$LFS/tools/bin:${PATH:-}"
export CC="${LFS_TGT}-gcc"
export AR="${LFS_TGT}-ar"
export RANLIB="${LFS_TGT}-ranlib"
export CFLAGS="-O2"
export CPPFLAGS="-I$LFS/usr/include"
export LDFLAGS="-L$LFS/usr/lib"
export PKG_CONFIG_SYSROOT_DIR="$LFS"
export PKG_CONFIG_LIBDIR="$LFS/usr/lib/pkgconfig:$LFS/usr/share/pkgconfig"
export PKG_CONFIG_PATH=""

WORK=$(mktemp -d "${TMPDIR:-/tmp}/lfs-ch-1450.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
tar -xJf "$SRC_TAR" -C "$WORK" --strip-components=1 2>/dev/null \
	|| tar -xzf "$SRC_TAR" -C "$WORK" --strip-components=1

cd "$WORK"
build_trip="$(uname -m)-unknown-$(uname -s | tr '[:upper:]' '[:lower:]')"
./configure \
	--prefix=/usr \
	--sysconfdir=/etc \
	--host="$LFS_TGT" \
	--build="$build_trip" \
	--without-kernel-modules \
	--without-x \
	--disable-multimon \
	--with-fuse=fuse3 \
	|| ./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--host="$LFS_TGT" \
		--build="$build_trip" \
		--without-kernel-modules

gmake -j"${LF_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)}"
gmake DESTDIR="$LFS" install

mkdir -p "$LFS/etc/lfs-from-freebsd"
cat > "$LFS/etc/lfs-from-freebsd/open-vm-tools.conf" <<'EOF'
# Installed by chapter 1450 — require vmtoolsd when running under VMware.
EOF

if [ -d "$LFS/usr/lib/systemd/system" ] || [ -d "$LFS/lib/systemd/system" ]; then
	UNIT_DIR="$LFS/usr/lib/systemd/system"
	[ -d "$UNIT_DIR" ] || UNIT_DIR="$LFS/lib/systemd/system"
	mkdir -p "$UNIT_DIR" "$LFS/etc/systemd/system/multi-user.target.wants"
	if [ ! -f "$UNIT_DIR/vmtoolsd.service" ]; then
		cat > "$UNIT_DIR/vmtoolsd.service" <<'EOF'
[Unit]
Description=Open VM Tools (vmtoolsd)
ConditionVirtualization=vmware
After=local-fs.target

[Service]
ExecStart=/usr/bin/vmtoolsd
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
	fi
	# Absolute unit path so DESTDIR is not baked into the enable link.
	_unit_abs=/usr/lib/systemd/system/vmtoolsd.service
	case "$UNIT_DIR" in
	*/lib/systemd/system) _unit_abs=/lib/systemd/system/vmtoolsd.service ;;
	esac
	ln -sfn "$_unit_abs" \
		"$LFS/etc/systemd/system/multi-user.target.wants/vmtoolsd.service"
fi

mkdir -p "${LF_CHAPTER_STATE:?LF_CHAPTER_STATE must be set}"
touch "${LF_CHAPTER_STATE}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done (open-vm-tools → $LFS) ==="
