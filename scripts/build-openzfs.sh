#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# build-openzfs.sh — OpenZFS for the FreeBSD-built Linux kernel.
#
# WHAT: Stage OpenZFS sources; try linuxulator build when possible; else mark
#       NEEDS_BUILDER for the Alpine guest path.
# WHY:  Installed root is ZFS (rpool/ROOT/lfs).
# HOST: FreeBSD orchestrator; module link usually needs a Linux ABI.
# OUT:  out/zfs/ (modules + utils) or out/zfs/NEEDS_BUILDER marker
# DOCS: docs/ZFS-ROOT.md, docs/BUILDER-GUEST.md

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

lf_start_log openzfs

lf_log "=== build-openzfs ${OPENZFS_VERSION} ==="
[ -f "$LF_OUT/linux/bzImage" ] || lf_die "kernel missing; run make kernel"
[ -d "$LF_OUT/linux/build" ] || lf_die "kernel build tree missing; run make kernel"
[ -d "$LF_OUT/linux/src" ] || lf_die "kernel src missing; run make kernel"

mkdir -p "$LF_OUT/zfs"
rm -rf "$LF_OUT/zfs/src"
mkdir -p "$LF_OUT/zfs/src"
tar -xzf "$LF_VENDOR/$OPENZFS_TARBALL" -C "$LF_OUT/zfs/src" --strip-components=1

KERNEL_SRC="$LF_OUT/linux/src"
KERNEL_OBJ="$LF_OUT/linux/build"
DEST="$LF_OUT/zfs/destdir"
rm -rf "$DEST"
mkdir -p "$DEST"

try_linuxulator_openzfs() {
	LXGCC="/compat/linux/usr/bin/gcc"
	[ -x "$LXGCC" ] || return 1
	command -v autoreconf >/dev/null 2>&1 || return 1
	lf_log "Attempting OpenZFS configure/build via linuxulator gcc"
	LF_LXLIB="$LF_OUT/linux-host-lib"
	mkdir -p "$LF_LXLIB"
	# Unversioned .so for -lz (Rocky/C7 often ship only libz.so.1).
	if [ -e /compat/linux/usr/lib64/libz.so.1 ]; then
		ln -sfn /compat/linux/usr/lib64/libz.so.1 "$LF_LXLIB/libz.so"
	elif [ -e /compat/linux/lib64/libz.so.1 ]; then
		ln -sfn /compat/linux/lib64/libz.so.1 "$LF_LXLIB/libz.so"
	fi
	(
		cd "$LF_OUT/zfs/src" || exit 1
		if [ ! -x configure ]; then
			autoreconf -fi || exit 1
		fi
		export CC="$LXGCC"
		export CXX="${LF_HOSTCXX:-/compat/linux/usr/bin/g++}"
		export PKG_CONFIG_PATH="/compat/linux/usr/lib64/pkgconfig:/compat/linux/usr/lib/pkgconfig"
		export LDFLAGS="-L$LF_LXLIB -L/compat/linux/usr/lib64 -L/compat/linux/lib64"
		export CPPFLAGS="-I/compat/linux/usr/include"
		export LIBS="-L$LF_LXLIB -lz"
		./configure \
			--prefix=/usr \
			--with-linux="$KERNEL_SRC" \
			--with-linux-obj="$KERNEL_OBJ" \
			--disable-sysvinit \
			--disable-systemd \
			--disable-pyzfs \
			--disable-nls || exit 1
		gmake -j"$(lf_jobs)" || exit 1
		gmake DESTDIR="$DEST" install || exit 1
	)
}

if [ -f "$LF_OUT/builder/state.env" ]; then
	# shellcheck disable=SC1091
	. "$LF_OUT/builder/state.env"
	lf_log "Builder state found ($BUILDER_VM_NAME); prefer guest build if linuxulator fails"
fi

STATUS="needs-builder"
if try_linuxulator_openzfs; then
	STATUS="linuxulator-ok"
	# Collect .ko modules if present
	mkdir -p "$LF_OUT/zfs/modules"
	find "$DEST" -name '*.ko' -exec cp -f {} "$LF_OUT/zfs/modules/" \; 2>/dev/null || true
	lf_log "OpenZFS installed to $DEST"
else
	lf_log "linuxulator OpenZFS build not ready — staging for builder guest"
	cat > "$LF_OUT/zfs/NEEDS_BUILDER" <<EOF
OpenZFS ${OPENZFS_VERSION} sources staged at out/zfs/src
Kernel: $KERNEL_SRC
Kernel obj: $KERNEL_OBJ

On the Linux builder (make builder && start):
  cd \$SHARED/out/zfs/src
  ./configure --with-linux=\$SHARED/out/linux/src --with-linux-obj=\$SHARED/out/linux/build
  make -j\$(nproc)
  make DESTDIR=\$SHARED/out/zfs/destdir install

Then: make iso  (to ship modules on live media) and make test-install
EOF
	if [ ! -f "$LF_OUT/builder/state.env" ]; then
		lf_log "Hint: ./scripts/builder-guest/create.sh"
	fi
fi

echo "$STATUS" > "$LF_OUT/zfs/STATUS"
lf_log "=== openzfs stage complete (status=$STATUS) ==="
