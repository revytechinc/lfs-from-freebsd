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

mkdir -p "$TREE/bin" "$TREE/sbin" "$TREE/etc" "$TREE/proc" "$TREE/sys" \
	"$TREE/dev" "$TREE/tmp" "$TREE/run" "$TREE/root" "$TREE/mnt" "$TREE/media" \
	"$TREE/media/cdrom" "$TREE/lib" "$TREE/usr/bin" "$TREE/usr/sbin" "$TREE/live/bin"
cp -f "$BB" "$TREE/bin/busybox"
chmod +x "$TREE/bin/busybox"
for applet in sh ash mount umount mkdir ls cat echo sleep ln cp mv rm chmod \
	chown grep sed awk find uname dmesg insmod modprobe lsmod tar gzip \
	touch sync yes printf head tail wc; do
	ln -sf busybox "$TREE/bin/$applet"
done
# Traditional paths for module helpers (install-to-zfs / init use these).
ln -sf ../bin/busybox "$TREE/sbin/insmod"
ln -sf ../bin/busybox "$TREE/sbin/modprobe"

cp -f "$LF_ROOT/scripts/install-to-zfs.sh" "$TREE/live/bin/install-to-zfs.sh"
chmod +x "$TREE/live/bin/install-to-zfs.sh"
ln -sf ../live/bin/install-to-zfs.sh "$TREE/sbin/install-to-zfs.sh" 2>/dev/null || true

# OpenZFS + installer helpers from Alpine-staged runtime (out/zfs/runtime).
RT="$LF_OUT/zfs/runtime"
if [ -f "$LF_OUT/zfs/STATUS" ] && [ "$(cat "$LF_OUT/zfs/STATUS")" = "linux-guest-ok" ] \
	&& [ -d "$RT/sbin" ]; then
	lf_log "Merging OpenZFS runtime into live rootfs"
	mkdir -p "$TREE/lib" "$TREE/usr/lib" "$TREE/lib/modules/lfs"
	cp -a "$RT/lib/"* "$TREE/lib/" 2>/dev/null || true
	cp -a "$RT/usr/lib/"* "$TREE/usr/lib/" 2>/dev/null || true
	cp -f "$RT/sbin/"* "$TREE/sbin/" 2>/dev/null || true
	[ -d "$RT/modules" ] && cp -f "$RT/modules/"*.ko "$TREE/lib/modules/lfs/" 2>/dev/null || true
	# Ensure musl-built tools see their libs without relying on live PATH quirks.
	cat > "$TREE/etc/ld-musl-path.env" <<'EOT'
# Sourced by install wrapper if needed
export LD_LIBRARY_PATH=/usr/lib:/lib
EOT
fi

# Merge live overlay
if [ -d "$LF_ROOT/overlays/live" ]; then
	( cd "$LF_ROOT/overlays/live" && tar cf - . ) | ( cd "$TREE" && tar xpf - )
fi

# Seed /dev nodes so early redirects work before devtmpfs is mounted
# (squashfs is RO — without these, `2>/dev/null` fails loudly).
mkdir -p "$TREE/dev" "$TREE/proc" "$TREE/sys" "$TREE/tmp" "$TREE/run"
if command -v mknod >/dev/null 2>&1; then
	mknod "$TREE/dev/null" c 1 3 2>/dev/null || true
	mknod "$TREE/dev/zero" c 1 5 2>/dev/null || true
	mknod "$TREE/dev/console" c 5 1 2>/dev/null || true
	mknod "$TREE/dev/tty" c 5 0 2>/dev/null || true
	chmod 666 "$TREE/dev/null" "$TREE/dev/zero" 2>/dev/null || true
fi

# Tiny /sbin/init for live squashfs path
cat > "$TREE/sbin/init" <<'EOT'
#!/bin/busybox sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LD_LIBRARY_PATH=/usr/lib:/lib
# Mount writable API filesystems first — do not redirect to /dev/null until
# after /dev is a real devtmpfs (squash root is read-only).
mount -t proc proc /proc || true
mount -t sysfs sys /sys || true
mount -t devtmpfs devtmpfs /dev || mount -t tmpfs tmpfs /dev || true
mkdir -p /dev/pts /tmp /run
mount -t devpts devpts /dev/pts 2>/dev/null || true
mount -t tmpfs tmpfs /tmp || true
mount -t tmpfs tmpfs /run || true
# Load ZFS modules for install-to-zfs when present on the live medium.
if [ -f /lib/modules/lfs/spl.ko ]; then
	if ! /bin/busybox insmod /lib/modules/lfs/spl.ko; then
		echo "WARN: insmod spl.ko failed — install-to-zfs will need a module rebuild"
	elif ! /bin/busybox insmod /lib/modules/lfs/zfs.ko; then
		echo "WARN: insmod zfs.ko failed — install-to-zfs will need a module rebuild"
	fi
fi
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
