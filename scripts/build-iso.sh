#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# build-iso.sh — BIOS + UEFI hybrid live ISO via Limine + xorriso.
#
# WHAT: Stage boot tree, install Limine BIOS and UEFI CD bits, write limine.conf,
#       embed kernel+initramfs, optional squashfs, produce out/lfs-from-freebsd.iso.
# WHY:  One medium must boot under legacy BIOS and UEFI (docs/BOOT-AND-ISO.md).
# HOST: FreeBSD with xorriso (and limine tools from the Limine source build).
# OUT:  out/lfs-from-freebsd.iso
# DOCS: docs/BOOT-AND-ISO.md

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

lf_start_log iso

lf_log "=== build-iso (BIOS + UEFI hybrid) ==="

[ -f "$LF_OUT/linux/bzImage" ] || lf_die "missing kernel; run make kernel"
[ -f "$LF_OUT/initramfs.img" ] || lf_die "missing initramfs; run make initramfs"

# --- build Limine from pinned sources (produces BIOS + UEFI CD images) ---
LIMINE_SRC="$LF_OUT/limine/src"
rm -rf "$LF_OUT/limine"
mkdir -p "$LIMINE_SRC"
tar -xJf "$LF_VENDOR/$LIMINE_TARBALL" -C "$LIMINE_SRC" --strip-components=1
(
	cd "$LIMINE_SRC" || exit 1
	./configure --enable-bios --enable-bios-cd --enable-uefi-x86-64 --enable-uefi-cd
	gmake -j"$(lf_jobs)"
)
LIMINE_BIN="$LIMINE_SRC"
[ -f "$LIMINE_BIN/bin/limine" ] || [ -f "$LIMINE_BIN/limine" ] || lf_die "limine binary missing after build"
LIMINE_TOOL="$LIMINE_BIN/bin/limine"
[ -x "$LIMINE_TOOL" ] || LIMINE_TOOL="$LIMINE_BIN/limine"

# --- stage ISO tree ---
TREE="$LF_OUT/iso/tree"
rm -rf "$TREE"
mkdir -p "$TREE/boot" "$TREE/EFI/BOOT" "$TREE/live"

cp -f "$LF_OUT/linux/bzImage" "$TREE/boot/vmlinuz"
cp -f "$LF_OUT/initramfs.img" "$TREE/boot/initramfs.img"

# Limine artifacts (names from Limine 8.x build)
for f in limine-bios.sys limine-bios-cd.bin limine-uefi-cd.bin limine-bios-pxe.bin; do
	if [ -f "$LIMINE_BIN/bin/$f" ]; then
		cp -f "$LIMINE_BIN/bin/$f" "$TREE/boot/$f"
	elif [ -f "$LIMINE_BIN/$f" ]; then
		cp -f "$LIMINE_BIN/$f" "$TREE/boot/$f"
	fi
done
# UEFI removable path
UEFI_IMG=""
for c in \
	"$LIMINE_BIN/bin/BOOTX64.EFI" \
	"$LIMINE_BIN/bin/limine-uefi-x86_64.efi" \
	"$LIMINE_BIN/BOOTX64.EFI"
do
	if [ -f "$c" ]; then
		cp -f "$c" "$TREE/EFI/BOOT/BOOTX64.EFI"
		UEFI_IMG="$c"
		break
	fi
done
[ -f "$TREE/EFI/BOOT/BOOTX64.EFI" ] || lf_log "WARN: BOOTX64.EFI not found — check Limine build outputs"

# Shared limine.conf (BIOS + UEFI)
CMDLINE="lfs.live=1 console=tty0 console=ttyS0,115200n8"
sed -e "s|@@TITLE@@|Linux on FreeBSD (live)|g" \
	-e "s|@@KERNEL_PATH@@|/boot/vmlinuz|g" \
	-e "s|@@INITRD_PATH@@|/boot/initramfs.img|g" \
	-e "s|@@CMDLINE@@|${CMDLINE}|g" \
	"$LF_ROOT/config/limine/limine.conf.in" > "$TREE/boot/limine.conf"
# Limine 8 may also look for limine.conf at ISO root
cp -f "$TREE/boot/limine.conf" "$TREE/limine.conf"

# Live rootfs squashfs if present
if [ -f "$LF_OUT/rootfs/rootfs.squashfs" ]; then
	cp -f "$LF_OUT/rootfs/rootfs.squashfs" "$TREE/live/rootfs.squashfs"
elif [ -d "$LF_OUT/rootfs/tree" ]; then
	if command -v mksquashfs >/dev/null 2>&1; then
		mksquashfs "$LF_OUT/rootfs/tree" "$TREE/live/rootfs.squashfs" -comp xz -noappend
	else
		lf_log "WARN: mksquashfs missing; ISO will boot to initramfs shell only"
	fi
fi

# Embed installer script on medium for live use
mkdir -p "$TREE/live/bin"
cp -f "$LF_ROOT/scripts/install-to-zfs.sh" "$TREE/live/bin/install-to-zfs.sh"
chmod +x "$TREE/live/bin/install-to-zfs.sh"

ISO="$LF_OUT/lfs-from-freebsd.iso"
rm -f "$ISO"

# Require both BIOS and UEFI El Torito images
[ -f "$TREE/boot/limine-bios-cd.bin" ] || lf_die "missing limine-bios-cd.bin (BIOS El Torito)"
[ -f "$TREE/boot/limine-uefi-cd.bin" ] || lf_die "missing limine-uefi-cd.bin (UEFI El Torito)"

# xorriso hybrid: BIOS + UEFI (Limine upstream pattern for 8.x)
xorriso -as mkisofs -R -r -J -joliet-long \
	-V "LFS_FROM_FBSD" \
	-o "$ISO" \
	-b boot/limine-bios-cd.bin \
	-no-emul-boot -boot-load-size 4 -boot-info-table \
	--efi-boot boot/limine-uefi-cd.bin \
	-efi-boot-part --efi-boot-image \
	"$TREE"

# Hybrid MBR for USB/dd BIOS boots
"$LIMINE_TOOL" bios-install "$ISO" || lf_die "limine bios-install on ISO failed"

ls -la "$ISO"
lf_log "=== ISO OK (BIOS+UEFI): $ISO ==="
lf_log "Verify: xorriso -indev $ISO -report_el_torito as_mkisofs | head"
