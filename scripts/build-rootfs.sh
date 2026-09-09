#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# build-rootfs.sh — assemble live rootfs tree (+ squashfs when possible).
#
# WHAT: Minimal live tree from BusyBox + overlays/live; later LFS DESTDIR merges here.
# WHY:  Live medium needs an installer shell; desktop stays out of live (Milestone C).
# HOST: FreeBSD.
# OUT:  out/rootfs/tree, optional out/rootfs/rootfs.squashfs
# DOCS: docs/BOOT-AND-ISO.md, docs/DESKTOP-PLASMA6.md

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

lf_start_log rootfs

lf_log "=== build-rootfs (live; no Plasma) ==="

TREE="$LF_OUT/rootfs/tree"
rm -rf "$TREE"
mkdir -p "$TREE"

BB="${LF_OUT}/busybox/busybox"
[ -x "$BB" ] || lf_die "busybox missing; run make busybox"

mkdir -p "$TREE"/{bin,sbin,etc,proc,sys,dev,tmp,run,root,mnt,media,lib,usr/bin,usr/sbin,live/bin}
cp -f "$BB" "$TREE/bin/busybox"
chmod +x "$TREE/bin/busybox"
for applet in sh ash mount umount mkdir ls cat echo sleep ln cp mv rm chmod \
	chown grep sed awk find uname dmesg; do
	ln -sf busybox "$TREE/bin/$applet"
done

cp -f "$LF_ROOT/scripts/install-to-zfs.sh" "$TREE/live/bin/install-to-zfs.sh"
chmod +x "$TREE/live/bin/install-to-zfs.sh"
ln -sf ../live/bin/install-to-zfs.sh "$TREE/sbin/install-to-zfs.sh" 2>/dev/null || true

# Merge live overlay
if [ -d "$LF_ROOT/overlays/live" ]; then
	( cd "$LF_ROOT/overlays/live" && tar cf - . ) | ( cd "$TREE" && tar xpf - )
fi

# Tiny /sbin/init for live squashfs path
cat > "$TREE/sbin/init" <<'EOT'
#!/bin/busybox sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sys /sys 2>/dev/null || true
mount -t devtmpfs dev /dev 2>/dev/null || true
echo "lfs-from-freebsd live root"
echo "Install to ZFS: install-to-zfs.sh --help"
echo "Desktop (Plasma 6/SDDM) applies after install — docs/DESKTOP-PLASMA6.md"
exec /bin/busybox sh
EOT
chmod +x "$TREE/sbin/init"

if command -v mksquashfs >/dev/null 2>&1; then
	mksquashfs "$TREE" "$LF_OUT/rootfs/rootfs.squashfs" -comp xz -noappend
	lf_log "squashfs: $LF_OUT/rootfs/rootfs.squashfs"
else
	lf_log "WARN: mksquashfs not installed; ISO may lack squashfs"
fi

lf_log "=== rootfs OK ==="
