#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# build-busybox-initramfs.sh — BusyBox + /init → initramfs.img
#
# WHAT: Stage BusyBox (static bootstrap or future cross-build), write /init
#       that supports live + ZFS root= cmdline, pack cpio.gz initramfs.
# WHY:  Early userspace before LFS chapters fill the real rootfs.
# HOST: FreeBSD for packing; BusyBox binary must be Linux ELF.
# OUT:  out/busybox/busybox, out/initramfs.img
# ARGS: optional "busybox-only" to skip packing initramfs
# DOCS: docs/BOOT-AND-ISO.md, docs/ZFS-ROOT.md

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

MODE="${1:-all}"
lf_start_log initramfs

lf_log "=== busybox/initramfs (mode=$MODE) ==="

BBDIR="$LF_OUT/busybox"
mkdir -p "$BBDIR"
BB="$BBDIR/busybox"

if [ -x "$LF_VENDOR/busybox-static" ]; then
	lf_verify_required "$LF_VENDOR/busybox-static" "$BUSYBOX_STATIC_SHA256"
	cp -f "$LF_VENDOR/busybox-static" "$BB"
	chmod +x "$BB"
	lf_log "Using vendor BusyBox static bootstrap"
elif [ -x "$BB" ]; then
	lf_log "Using existing $BB"
else
	# Extract sources for later cross-build; for now require bootstrap.
	tar -xjf "$LF_VENDOR/$BUSYBOX_TARBALL" -C "$BBDIR"
	lf_die "No Linux BusyBox binary yet. Re-run make fetch (static URL) or implement cross-build. See docs/TROUBLESHOOTING.md"
fi

file "$BB" || true

if [ "$MODE" = "busybox-only" ]; then
	lf_log "=== busybox-only done ==="
	exit 0
fi

# --- assemble initramfs tree ---
# FreeBSD /bin/sh has no brace expansion — list dirs explicitly.
IR="$LF_OUT/initramfs/root"
rm -rf "$IR"
mkdir -p "$IR/bin" "$IR/sbin" "$IR/dev" "$IR/proc" "$IR/sys" \
	"$IR/run" "$IR/tmp" "$IR/newroot" "$IR/mnt" "$IR/lib" "$IR/lib64" "$IR/etc"
cp -f "$BB" "$IR/bin/busybox"
chmod +x "$IR/bin/busybox"
# Do NOT execute the Linux ELF BusyBox on FreeBSD. Create a minimal applet
# symlink set for the initramfs (extend as needed).
for applet in sh ash mount umount mkdir ls cat echo sleep modprobe switch_root \
	cpio gzip gunzip find grep sed awk ln cp mv rm chmod chown mknod \
	uname dmesg blkid zpool zfs; do
	ln -sf busybox "$IR/bin/$applet"
done
# sbin copies of common admin names
mkdir -p "$IR/sbin"
for applet in modprobe switch_root mount umount zpool zfs; do
	ln -sf ../bin/busybox "$IR/sbin/$applet"
done

# /init — live vs ZFS installed (firmware-agnostic: BIOS and UEFI both reach here)
cat > "$IR/init" <<'INIT'
#!/bin/busybox sh
# lfs-from-freebsd initramfs — see docs/BOOT-AND-ISO.md
export PATH=/bin:/sbin

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || mount -t tmpfs tmpfs /dev

CMDLINE=$(cat /proc/cmdline 2>/dev/null || true)
echo "lfs-from-freebsd init; cmdline: $CMDLINE"

live=0
rootzfs=""
set -f
for tok in $CMDLINE; do
	case "$tok" in
	lfs.live=1|lfs.live=yes) live=1 ;;
	root=ZFS=*) rootzfs="${tok#root=ZFS=}" ;;
	root=zfs:*) rootzfs="${tok#root=zfs:}" ;;
	esac
done
set +f

# Load ZFS if modules present (installed path; live may skip).
if [ -n "$rootzfs" ] && [ "$live" -eq 0 ]; then
	echo "ZFS root requested: $rootzfs"
	case "$rootzfs" in
	rpool/ROOT/*) ;;
	*)
		echo "ERROR: refusing unexpected ZFS root dataset: $rootzfs"
		exec /bin/busybox sh
		;;
	esac
	modprobe zfs 2>/dev/null || true
	zpool import -N rpool 2>/dev/null || true
	if mount -t zfs "$rootzfs" /newroot 2>/dev/null; then
		echo "Mounted $rootzfs on /newroot; switch_root"
		exec switch_root /newroot /sbin/init
	fi
	echo "ERROR: failed to mount ZFS root $rootzfs"
	exec /bin/busybox sh
fi

# Live: try squashfs on optical/virtio CD only (not arbitrary disks).
if [ "$live" -eq 1 ]; then
	echo "Live mode — attempting squashfs / installer shell"
	mkdir -p /mnt/medium /mnt/squash
	for d in /dev/sr0 /dev/cd0; do
		[ -b "$d" ] || continue
		mount -o ro "$d" /mnt/medium 2>/dev/null || continue
		if [ -f /mnt/medium/live/rootfs.squashfs ]; then
			if mount -t squashfs -o ro /mnt/medium/live/rootfs.squashfs /mnt/squash 2>/dev/null; then
				if [ -x /mnt/squash/sbin/init ] || [ -x /mnt/squash/init ]; then
					exec switch_root /mnt/squash /sbin/init
				fi
			fi
		fi
	done
	echo "Live squashfs not mounted; dropping to rescue shell."
	echo "Installer: /bin/install-to-zfs.sh (when present on medium)."
	exec /bin/busybox sh
fi

echo "No lfs.live / root=ZFS; rescue shell."
exec /bin/busybox sh
INIT
chmod +x "$IR/init"

# Pack cpio gz (newc). FreeBSD find + cpio.
IMG="$LF_OUT/initramfs.img"
(
	cd "$IR" || exit 1
	find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$IMG"
) || lf_die "cpio/gzip initramfs failed"

ls -la "$IMG"
lf_log "=== initramfs OK: $IMG ==="
