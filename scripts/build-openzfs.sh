#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# build-openzfs.sh — stage OpenZFS for the Linux builder guest.
#
# WHAT: Extract pinned OpenZFS against the FreeBSD-built Linux tree; leave a
#       builder recipe. No linuxulator.
# WHY:  OpenZFS module/userland link needs a real Linux userspace ABI; that is
#       the Alpine/bhyve builder — FreeBSD only orchestrates.
# HOST: FreeBSD.
# OUT:  out/zfs/src, out/zfs/NEEDS_BUILDER, out/zfs/STATUS
# DOCS: docs/ZFS-ROOT.md, docs/BUILDER-GUEST.md, docs/ARCHITECTURE.md

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

lf_start_log openzfs

lf_log "=== build-openzfs ${OPENZFS_VERSION} (stage for builder; pure FreeBSD host) ==="
[ -f "$LF_OUT/linux/bzImage" ] || lf_die "kernel missing; run make kernel"
[ -d "$LF_OUT/linux/build" ] || lf_die "kernel build tree missing; run make kernel"
[ -d "$LF_OUT/linux/src" ] || lf_die "kernel src missing; run make kernel"

mkdir -p "$LF_OUT/zfs"
rm -rf "$LF_OUT/zfs/src" "$LF_OUT/zfs/destdir"
mkdir -p "$LF_OUT/zfs/src" "$LF_OUT/zfs/destdir"
tar -xzf "$LF_VENDOR/$OPENZFS_TARBALL" -C "$LF_OUT/zfs/src" --strip-components=1

KERNEL_SRC="$LF_OUT/linux/src"
KERNEL_OBJ="$LF_OUT/linux/build"

cat > "$LF_OUT/zfs/NEEDS_BUILDER" <<EOF
OpenZFS ${OPENZFS_VERSION} sources: out/zfs/src
FreeBSD-built kernel src: $KERNEL_SRC
FreeBSD-built kernel obj: $KERNEL_OBJ

Pure FreeBSD policy: do NOT build OpenZFS under linuxulator.
On the Linux builder guest (gmake builder && start + SSH):

  cd \$SHARED/out/zfs/src
  ./configure --prefix=/usr \\
    --with-linux=\$SHARED/out/linux/src \\
    --with-linux-obj=\$SHARED/out/linux/build
  make -j\$(nproc)
  make DESTDIR=\$SHARED/out/zfs/destdir install

Then refresh the live ISO and run make test-install.
EOF

if [ -f "$LF_OUT/builder/state.env" ]; then
	# shellcheck disable=SC1091
	. "$LF_OUT/builder/state.env"
	lf_log "Builder state present ($BUILDER_VM_NAME) — run guest OpenZFS build next"
else
	lf_log "No builder yet — ./scripts/builder-guest/create.sh && start.sh"
fi

echo "needs-builder" > "$LF_OUT/zfs/STATUS"
lf_log "=== openzfs staged (status=needs-builder) ==="
