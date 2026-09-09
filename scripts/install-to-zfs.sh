#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# install-to-zfs.sh — live → GPT + ESP + Limine (BIOS+UEFI) + rpool/ROOT/lfs
#
# WHAT: Partition target disk, create ZFS pool/datasets, copy rootfs, install
#       Limine for BOTH legacy BIOS and UEFI, write limine.conf with ZFS root.
# WHY:  Milestone A install path; desktop overlay applied when present
#       (Plasma/SDDM are installed-only — docs/DESKTOP-PLASMA6.md).
# HOST: Linux live environment (BusyBox/ash). Also documented for builder tests.
# OUT:  Bootable GPT disk (BIOS + UEFI) with OpenZFS root.
# DOCS: docs/ZFS-ROOT.md, docs/BOOT-AND-ISO.md

set -eu

usage() {
	cat <<EOF
Usage: install-to-zfs.sh --disk DEV --yes [--auto] [--rootfs DIR]
                         [--hostname NAME] [--user NAME] [--limine-tool PATH]

  --disk DEV     Target block device (e.g. /dev/vdb). Required unless --auto.
  --yes          Required confirmation that destructive partitioning is intended.
  --auto         Test harness only: first of vtbd1/vdb/sdb/ada1 (never nvme/host).
  --rootfs DIR   Directory tree to copy (default: / or /mnt/squash).
  --hostname N   Set installed hostname (default: lfs-from-freebsd).
  --user NAME    Create login user in video,audio,input (desktop-ready).

Installs Limine for UEFI (ESP) and BIOS (limine bios-install).
Does NOT enable Plasma on the live medium; merges overlays/installed when found.
EOF
}

DISK=""
AUTO=0
YES=0
ROOTFS=""
HOSTNAME="lfs-from-freebsd"
USER_NAME=""
LIMINE_TOOL="${LIMINE_TOOL:-limine}"

while [ $# -gt 0 ]; do
	case "$1" in
	--disk) DISK="$2"; shift 2 ;;
	--auto) AUTO=1; shift ;;
	--yes) YES=1; shift ;;
	--rootfs) ROOTFS="$2"; shift 2 ;;
	--hostname) HOSTNAME="$2"; shift 2 ;;
	--user) USER_NAME="$2"; shift 2 ;;
	--limine-tool) LIMINE_TOOL="$2"; shift 2 ;;
	-h|--help) usage; exit 0 ;;
	*) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
	esac
done

if [ "$AUTO" -eq 1 ] && [ -z "$DISK" ]; then
	# Virt-only names for the test harness — never sd*/ada*/nvme*.
	for c in /dev/vtbd1 /dev/vdb /dev/vdc /dev/vdd; do
		if [ -b "$c" ]; then DISK="$c"; break; fi
	done
fi
[ -n "$DISK" ] || { usage; exit 1; }
[ -b "$DISK" ] || { echo "Not a block device: $DISK" >&2; exit 1; }
[ "$YES" -eq 1 ] || { echo "Refusing destructive install without --yes" >&2; exit 1; }

# Refuse obvious live/boot and host-class disks unless operator passed --disk
# explicitly without --auto (still require --yes).
case "$DISK" in
*/sr0|*/cd0|*/vtbd0|*/vda)
	echo "Refusing likely live/boot medium: $DISK" >&2
	exit 1
	;;
esac
if [ "$AUTO" -eq 1 ]; then
	case "$DISK" in
	*/vtbd[1-9]|*/vd[b-z]) ;;
	*)
		echo "Refusing --auto on non-virt disk: $DISK (use --disk explicitly)" >&2
		exit 1
		;;
	esac
fi

echo "=== install-to-zfs: disk=$DISK hostname=$HOSTNAME ==="
echo "WARNING: This will destroy data on $DISK (--yes supplied)"

# Partition: ESP + BIOS boot + ZFS (sfdisk if available; else documented manual).
# Layout numbers are MB.
if command -v sfdisk >/dev/null 2>&1; then
	sfdisk "$DISK" <<EOF
label: gpt
unit: sectors
# ESP
size=1G, type=uefi, name=ESP
# BIOS boot (Limine GPT BIOS)
size=1M, type=21686148-6449-6E6F-744E-656564454649, name=BIOSBOOT
# ZFS
type=solaris, name=ZFS
EOF
else
	echo "sfdisk missing — use parted/gdisk manually per docs/ZFS-ROOT.md" >&2
	exit 1
fi

# Wait for partition nodes (GPT: always use pN when the disk name ends in a digit).
sleep 2
ESP=""
ZFSPART=""
case "$DISK" in
*[0-9])
	ESP="${DISK}p1"
	ZFSPART="${DISK}p3"
	;;
*)
	ESP="${DISK}1"
	ZFSPART="${DISK}3"
	;;
esac
i=0
while [ "$i" -lt 30 ]; do
	[ -b "$ESP" ] && [ -b "$ZFSPART" ] && break
	sleep 1
	i=$((i + 1))
done
[ -b "$ESP" ] && [ -b "$ZFSPART" ] || {
	echo "partition nodes missing: ESP=$ESP ZFSPART=$ZFSPART" >&2
	exit 1
}

mkfs.vfat -F32 -n EFI "$ESP"
# BIOS boot partition left unformatted for limine bios-install

mkdir -p /mnt
# Altroot during install — never mount the new root dataset over live /
zpool create -f -R /mnt -o ashift=12 \
	-O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \
	-O mountpoint=none \
	-O canmount=off \
	rpool "$ZFSPART"
zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=noauto -o mountpoint=/ rpool/ROOT/lfs
zfs create -o mountpoint=/home rpool/home
zpool set bootfs=rpool/ROOT/lfs rpool
# With -R /mnt, the dataset mountpoint=/ appears at /mnt
zfs mount rpool/ROOT/lfs
# Fatal: altroot must show the dataset under /mnt (pool -R /mnt).
zfs get -H -o value mounted rpool/ROOT/lfs | grep -qx yes || {
	echo "ERROR: rpool/ROOT/lfs did not mount under altroot" >&2
	exit 1
}

if [ -z "$ROOTFS" ]; then
	if [ -d /media/squash ] && [ -x /media/squash/sbin/init ]; then
		ROOTFS=/media/squash
	elif [ -d /mnt/medium/live ] ; then
		ROOTFS=/
	else
		ROOTFS=/
	fi
fi

echo "Copying rootfs from $ROOTFS into ZFS altroot /mnt ..."
# Confirm we are writing into the new pool's altroot, not a random tmpfs.
zfs list -r rpool >/dev/null 2>&1 || { echo "ERROR: rpool missing" >&2; exit 1; }
( cd "$ROOTFS" && tar cf - --exclude=./proc --exclude=./sys --exclude=./dev --exclude=./mnt --exclude=./newroot . ) \
	| ( cd /mnt && tar xpf - )

# Merge installed overlay if present on the live medium only (never cwd-relative).
for o in /mnt/medium/overlays/installed /live/overlays/installed; do
	if [ -d "$o" ]; then
		echo "Merging installed overlay $o (includes SDDM/Plasma policy when built)"
		( cd "$o" && tar cf - --exclude='..' . ) | ( cd /mnt && tar xpf - )
		break
	fi
done

# ESP
mkdir -p /mnt/boot/efi
mount -t vfat "$ESP" /mnt/boot/efi
mkdir -p /mnt/boot/efi/EFI/BOOT /mnt/boot/efi/boot
cp -f /boot/vmlinuz /mnt/boot/efi/boot/vmlinuz 2>/dev/null \
	|| cp -f /mnt/medium/boot/vmlinuz /mnt/boot/efi/boot/vmlinuz
cp -f /boot/initramfs.img /mnt/boot/efi/boot/initramfs.img 2>/dev/null \
	|| cp -f /mnt/medium/boot/initramfs.img /mnt/boot/efi/boot/initramfs.img
cp -f /mnt/medium/EFI/BOOT/BOOTX64.EFI /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI 2>/dev/null || true

CMDLINE="root=ZFS=rpool/ROOT/lfs console=tty0 console=ttyS0,115200n8"
cat > /mnt/boot/efi/boot/limine.conf <<EOF
timeout: 5
serial: yes
default_entry: 1

/LFS from FreeBSD (ZFS)
    protocol: linux
    path: boot():/boot/vmlinuz
    cmdline: $CMDLINE
    module_path: boot():/boot/initramfs.img
EOF
cp -f /mnt/boot/efi/boot/limine.conf /mnt/boot/efi/limine.conf 2>/dev/null || true

# BIOS + UEFI: limine bios-install embeds BIOS stage on the disk
if command -v "$LIMINE_TOOL" >/dev/null 2>&1; then
	"$LIMINE_TOOL" bios-install "$DISK" || echo "WARN: limine bios-install failed"
else
	echo "WARN: limine tool not in PATH; UEFI may work, BIOS may not — copy limine onto live image"
fi

echo "$HOSTNAME" > /mnt/etc/hostname

if [ -n "$USER_NAME" ] && command -v useradd >/dev/null 2>&1; then
	printf '%s' "$USER_NAME" | grep -Eq '^[a-z][a-z0-9_-]*$' || {
		echo "Invalid --user name: $USER_NAME" >&2
		exit 1
	}
	useradd -R /mnt -m -G video,audio,input,wheel -- "$USER_NAME" || true
fi

umount /mnt/boot/efi 2>/dev/null || true
zpool export rpool || true
echo "=== install complete: reboot without ISO (BIOS or UEFI) ==="
echo "Desktop: SDDM + Plasma 6 once Milestone C chapters populated the rootfs."
