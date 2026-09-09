#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# build-openzfs.sh — OpenZFS for the FreeBSD-built Linux kernel.
#
# WHAT: Prefer building in the Linux builder guest against out/linux; record
#       status. FreeBSD-native configure of OpenZFS is often impossible.
# WHY:  Installed root is ZFS (rpool/ROOT/lfs).
# HOST: FreeBSD orchestrator; heavy lifting may be Linux guest.
# OUT:  out/zfs/ (modules + utils) or out/zfs/NEEDS_BUILDER marker
# DOCS: docs/ZFS-ROOT.md, docs/BUILDER-GUEST.md

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

lf_start_log openzfs

lf_log "=== build-openzfs ${OPENZFS_VERSION} ==="
[ -d "$LF_OUT/linux/build" ] || lf_die "kernel build tree missing; run make kernel"

mkdir -p "$LF_OUT/zfs"
# Extract sources for the builder to consume.
rm -rf "$LF_OUT/zfs/src"
mkdir -p "$LF_OUT/zfs/src"
tar -xzf "$LF_VENDOR/$OPENZFS_TARBALL" -C "$LF_OUT/zfs/src" --strip-components=1

# Attempt a Linuxulator/chroot-free detection: if we have a builder SSH, use it.
if [ -f "$LF_OUT/builder/state.env" ]; then
	# shellcheck disable=SC1091
	. "$LF_OUT/builder/state.env"
	lf_log "Builder state found; remote OpenZFS build should be invoked via builder-guest scripts"
	echo "pending-remote" > "$LF_OUT/zfs/STATUS"
else
	lf_log "No builder guest yet — staging OpenZFS sources only."
	lf_log "Create builder with: make builder  (see docs/BUILDER-GUEST.md)"
	cat > "$LF_OUT/zfs/NEEDS_BUILDER" <<EOF
OpenZFS ${OPENZFS_VERSION} sources staged at out/zfs/src
Kernel build at out/linux/build
Configure on Linux with:
  ./configure --with-linux=\$KERNEL_SRC --with-linux-obj=\$KERNEL_OBJ
  make -j\$(nproc) && make install DESTDIR=...
EOF
	echo "needs-builder" > "$LF_OUT/zfs/STATUS"
fi

lf_log "=== openzfs stage complete (status=$(cat "$LF_OUT/zfs/STATUS")) ==="
