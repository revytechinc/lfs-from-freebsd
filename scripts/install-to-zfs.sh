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

# Alpine-musl OpenZFS tools on the live medium need these paths.
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-/usr/lib:/lib}"
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:${PATH:-}"

usage() {
	cat <<EOF
Usage: install-to-zfs.sh --disk DEV --yes [--auto] [--rootfs DIR]
                         [--hostname NAME] [--user NAME] [--limine-tool PATH]

  --disk DEV     Target block device (e.g. /dev/vdb). Required unless --auto.
  --yes          Required confirmation that destructive partitioning is intended.
  --auto         Test harness only: first of vtbd1/vdb/vdc/vdd (never nvme/host/vda).
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
	# Test harness only: second virt disk — never the live boot disk, never host NVMe.
	for c in /dev/vtbd1 /dev/vdb /dev/vdc /dev/vdd; do
		if [ -b "$c" ]; then DISK="$c"; break; fi
	done
fi
[ -n "$DISK" ] || { usage; exit 1; }
[ -b "$DISK" ] || { echo "Not a block device: $DISK" >&2; exit 1; }
[ "$YES" -eq 1 ] || { echo "Refusing destructive install without --yes" >&2; exit 1; }

# Refuse optical and the live boot disk. Host-class names are blocked for
# --auto only; explicit --disk may target VMware /dev/sda etc.
case "$DISK" in
*/sr0|*/cd0|*/vtbd0|*/nvme*)
	echo "Refusing likely live/boot/host disk: $DISK" >&2
	exit 1
	;;
*/vda)
	if [ "$AUTO" -eq 1 ]; then
		echo "Refusing --auto on /dev/vda; pass --disk explicitly for live-ISO installs" >&2
		exit 1
	fi
	;;
esac
if [ "$AUTO" -eq 1 ]; then
	case "$DISK" in
	*/vtbd[1-9]|*/vd[b-z]) ;;
	*/sd[a-z]|*/ada[0-9]*)
		echo "Refusing --auto on host-class disk: $DISK (use --disk explicitly)" >&2
		exit 1
		;;
	*)
		echo "Refusing --auto on unexpected disk: $DISK (use --disk explicitly)" >&2
		exit 1
		;;
	esac
fi

echo "=== install-to-zfs: disk=$DISK hostname=$HOSTNAME ==="
echo "WARNING: This will destroy data on $DISK (--yes supplied)"

# OpenZFS is out-of-tree; live init may have skipped a failed load. Load now
# and fail loudly so we do not proceed to zpool without the module.
lf_insmod() {
	if command -v insmod >/dev/null 2>&1; then
		insmod "$@"
	elif [ -x /bin/busybox ]; then
		/bin/busybox insmod "$@"
	else
		return 127
	fi
}
if ! grep -q '^zfs ' /proc/modules 2>/dev/null; then
	if [ -f /lib/modules/lfs/spl.ko ]; then
		lf_insmod /lib/modules/lfs/spl.ko || {
			echo "ERROR: insmod spl.ko failed (rebuild OpenZFS for this kernel)" >&2
			exit 1
		}
		lf_insmod /lib/modules/lfs/zfs.ko || {
			echo "ERROR: insmod zfs.ko failed (rebuild OpenZFS for this kernel)" >&2
			exit 1
		}
	else
		echo "ERROR: no /lib/modules/lfs/*.ko on live medium" >&2
		exit 1
	fi
fi

# Partition: ESP + BIOS boot + ZFS (sector units only — Alpine sfdisk has no
# unit: MiB). Do not use type=solaris: util-linux 2.40.4 sfdisk rejects it with
# "Failed to add #3 partition: Invalid argument"; use the ZFS GPT GUID.
if command -v sfdisk >/dev/null 2>&1; then
	sfdisk -W always "$DISK" <<EOF
label: gpt
first-lba: 2048
size=1048576, type=uefi, name=ESP
size=32768, type=21686148-6449-6E6F-744E-656564454649, name=BIOSBOOT
type=6A898CC3-1DD2-11B2-99A6-080020736631, name=ZFS
EOF
	# virtio/bhyve often fails BLKRRPART; force partition nodes.
	partx -u "$DISK" 2>/dev/null || true
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

# Locate the live ISO (kernel + Limine EFI). Prefer paths that survive
# switch_root; remount the optical device if needed. Never use /mnt here —
# that becomes the ZFS altroot next.
MEDIUM=""
for d in /media/cdrom /run/live-medium; do
	if [ -f "$d/boot/vmlinuz" ]; then MEDIUM="$d"; break; fi
done
if [ -z "$MEDIUM" ]; then
	mkdir -p /media/cdrom
	for c in /dev/sr0 /dev/cd0; do
		[ -b "$c" ] || continue
		mount -o ro "$c" /media/cdrom 2>/dev/null || continue
		if [ -f /media/cdrom/boot/vmlinuz ]; then
			MEDIUM=/media/cdrom
			break
		fi
		umount /media/cdrom 2>/dev/null || true
	done
fi
[ -n "$MEDIUM" ] || {
	echo "ERROR: live medium with /boot/vmlinuz not found (need /media/cdrom)" >&2
	exit 1
}
echo "Live medium: $MEDIUM"

# Live squashfs is read-only — ZFS altroot needs a writable parent for
# mountpoint directories (/mnt/home etc.).
if touch /mnt/.lf_rw_probe 2>/dev/null; then
	rm -f /mnt/.lf_rw_probe
else
	mkdir -p /mnt
	mount -t tmpfs -o size=512M tmpfs /mnt
fi

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
	else
		ROOTFS=/
	fi
fi

echo "Copying rootfs from $ROOTFS into ZFS altroot /mnt ..."
# Confirm we are writing into the new pool's altroot, not a random tmpfs.
zfs list -r rpool >/dev/null 2>&1 || { echo "ERROR: rpool missing" >&2; exit 1; }
( cd "$ROOTFS" && tar cf - --one-file-system \
	--exclude=./proc --exclude=./sys --exclude=./dev --exclude=./mnt --exclude=./newroot \
	--exclude=./media/cdrom --exclude=./run/live-medium . ) \
	| ( cd /mnt && tar xpf - )

# Empty dirs skipped by tar --exclude; installed init needs them.
mkdir -p /mnt/proc /mnt/sys /mnt/dev /mnt/tmp /mnt/run /mnt/home /mnt/root /mnt/mnt

# Replace live installer init with an installed-root init (Milestone A shell).
cat > /mnt/sbin/init <<'EOT'
#!/bin/busybox sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LD_LIBRARY_PATH=/usr/lib:/lib
mount -t proc proc /proc || true
mount -t sysfs sys /sys || true
mount -t devtmpfs devtmpfs /dev || mount -t tmpfs tmpfs /dev || true
mkdir -p /dev/pts /tmp /run
mount -t devpts devpts /dev/pts 2>/dev/null || true
mount -t tmpfs tmpfs /tmp || true
mount -t tmpfs tmpfs /run || true
# Load ZFS so datasets stay available for admin (already mounted as root).
if [ -f /lib/modules/lfs/spl.ko ] && ! grep -q '^zfs ' /proc/modules 2>/dev/null; then
	/bin/busybox insmod /lib/modules/lfs/spl.ko 2>/dev/null || true
	/bin/busybox insmod /lib/modules/lfs/zfs.ko 2>/dev/null || true
fi
echo "lfs-from-freebsd installed root (rpool/ROOT/lfs)"
echo "Hostname: $(cat /etc/hostname 2>/dev/null || echo unknown)"
exec /bin/busybox sh
EOT
chmod +x /mnt/sbin/init

# Merge installed overlay if present on the live medium only (never cwd-relative).
for o in "$MEDIUM/overlays/installed" /live/overlays/installed; do
	if [ -d "$o" ]; then
		echo "Merging installed overlay $o (includes SDDM/Plasma policy when built)"
		( cd "$o" && tar cf - --exclude='..' . ) | ( cd /mnt && tar xpf - )
		break
	fi
done

# ESP — kernel/initramfs/Limine come from the live ISO, not the squash root.
mkdir -p /mnt/boot/efi
mount -t vfat "$ESP" /mnt/boot/efi
mkdir -p /mnt/boot/efi/EFI/BOOT /mnt/boot/efi/boot
cp -f "$MEDIUM/boot/vmlinuz" /mnt/boot/efi/boot/vmlinuz
cp -f "$MEDIUM/boot/initramfs.img" /mnt/boot/efi/boot/initramfs.img
cp -f "$MEDIUM/EFI/BOOT/BOOTX64.EFI" /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI 2>/dev/null \
	|| cp -f "$MEDIUM/boot/BOOTX64.EFI" /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI 2>/dev/null \
	|| echo "WARN: BOOTX64.EFI not found on medium"

CMDLINE="root=ZFS=rpool/ROOT/lfs console=tty0 console=ttyS0,115200n8 efi=noruntime ibt=off"
cat > /mnt/boot/efi/boot/limine.conf <<EOF
timeout: 5
serial: yes
default_entry: 1

/Linux on FreeBSD (ZFS)
    protocol: linux
    kernel_path: boot():/boot/vmlinuz
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
zfs umount -a 2>/dev/null || true
zpool export rpool || true
echo "=== install complete: reboot without ISO (BIOS or UEFI) ==="
echo "Desktop: SDDM + Plasma 6 once Milestone C chapters populated the rootfs."
