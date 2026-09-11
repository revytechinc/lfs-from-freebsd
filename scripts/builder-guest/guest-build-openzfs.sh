#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# guest-build-openzfs.sh — run *inside* the Alpine builder guest.
#
# Expects virtio-9p share mounted at /mnt/lfs with out/ and vendor/.
# Builds OpenZFS against the FreeBSD-built Linux tree; installs to
# /mnt/lfs/out/zfs/destdir.

set -eu

LFS_MNT="${LFS_MNT:-/mnt/lfs}"
OUT="$LFS_MNT/out"
ZSRC="$OUT/zfs/src"
KSRC="$OUT/linux/src"
KOBJ="$OUT/linux/build"
DEST="$OUT/zfs/destdir"

[ -d "$ZSRC" ] || { echo "missing $ZSRC — mount 9p share first" >&2; exit 1; }
[ -d "$KSRC" ] || { echo "missing $KSRC" >&2; exit 1; }
[ -d "$KOBJ" ] || { echo "missing $KOBJ" >&2; exit 1; }

echo "=== guest OpenZFS build ==="
apk add --no-cache \
	build-base autoconf automake libtool linux-headers \
	zlib-devel openssl-devel attr-devel util-linux \
	python3 py3-setuptools git bash

cd "$ZSRC"
if [ ! -x ./configure ]; then
	autoreconf -fi
fi

./configure \
	--prefix=/usr \
	--with-linux="$KSRC" \
	--with-linux-obj="$KOBJ" \
	--disable-sysvinit \
	--disable-pyzfs \
	--disable-nls

make -j"$(nproc)"
rm -rf "$DEST"
mkdir -p "$DEST"
make DESTDIR="$DEST" install

mkdir -p "$OUT/zfs/modules"
find "$DEST" -name '*.ko' -exec cp -f {} "$OUT/zfs/modules/" \;
echo "linux-guest-ok" > "$OUT/zfs/STATUS"
echo "=== OpenZFS installed to $DEST ==="
ls -la "$OUT/zfs/modules" || true
