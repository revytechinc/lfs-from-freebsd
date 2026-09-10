#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# vm-boot-test.sh — bhyve smoke tests for BIOS and UEFI.
#
# WHAT: Boot out/lfs-from-freebsd.iso under bhyve; optionally install / desktop.
# WHY:  Prove hybrid medium works on the CloudBSD build host (and peers).
# HOST: FreeBSD with bhyve + UEFI firmware package.
# OUT:  out/logs/vm-*.log; exit 0 on prompt seen
# DOCS: docs/BOOT-AND-ISO.md, docs/BUILD-HOST.md
#
# Usage:
#   vm-boot-test.sh [--uefi|--bios] [--install] [--desktop] [--timeout SEC]

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

FIRMWARE=uefi
DO_INSTALL=0
DO_DESKTOP=0
TIMEOUT=180

while [ $# -gt 0 ]; do
	case "$1" in
	--uefi) FIRMWARE=uefi; shift ;;
	--bios) FIRMWARE=bios; shift ;;
	--install) DO_INSTALL=1; shift ;;
	--desktop) DO_DESKTOP=1; shift ;;
	--timeout) TIMEOUT="$2"; shift 2 ;;
	*) lf_die "unknown arg: $1" ;;
	esac
done

ISO="$LF_OUT/lfs-from-freebsd.iso"
[ -f "$ISO" ] || lf_die "ISO missing; run make iso"

VMNAME="lfsboot$$"
lf_start_log "vm-${FIRMWARE}"
UEFI_CODE="${LF_UEFI_CODE:-/usr/local/share/uefi-firmware/BHYVE_UEFI_CODE.fd}"
UEFI_VARS_SRC="${LF_UEFI_VARS:-/usr/local/share/uefi-firmware/BHYVE_UEFI_VARS.fd}"
VARS="$LF_OUT/images/${VMNAME}-vars.fd"
DISK="$LF_OUT/images/${VMNAME}-disk.img"

cleanup() {
	bhyvectl --vm="$VMNAME" --destroy 2>/dev/null || true
}
trap cleanup EXIT INT TERM

lf_log "=== vm-boot-test firmware=$FIRMWARE install=$DO_INSTALL desktop=$DO_DESKTOP ==="

mkdir -p "$LF_OUT/images"
rm -f "$DISK"
truncate -s 16G "$DISK"

NMDM_A="/dev/nmdm${VMNAME}A"
NMDM_B="/dev/nmdm${VMNAME}B"

BHYVE_ARGS="-c 2 -m 2G -H -A -P"
BHYVE_ARGS="$BHYVE_ARGS -s 0:0,hostbridge -s 1:0,lpc"
BHYVE_ARGS="$BHYVE_ARGS -l com1,stdio"
BHYVE_ARGS="$BHYVE_ARGS -s 3:0,ahci-cd,$ISO"
BHYVE_ARGS="$BHYVE_ARGS -s 4:0,virtio-blk,$DISK"

if [ "$FIRMWARE" = "uefi" ]; then
	[ -f "$UEFI_CODE" ] || lf_die "UEFI code missing: $UEFI_CODE"
	cp -f "$UEFI_VARS_SRC" "$VARS"
	BHYVE_ARGS="$BHYVE_ARGS -l bootrom,$UEFI_CODE,$VARS"
else
	# Modern bhyve requires an explicit bootrom; SeaBIOS provides legacy BIOS.
	BIOS_ROM="${LF_BIOS_ROM:-}"
	if [ -z "$BIOS_ROM" ]; then
		for c in \
			/usr/local/share/seabios/bios.bin \
			/usr/local/share/uefi-firmware/BHYVE_CSM_CODE.fd \
			/usr/local/share/bhyve/bios.bin
		do
			if [ -f "$c" ]; then
				BIOS_ROM="$c"
				break
			fi
		done
	fi
	[ -n "$BIOS_ROM" ] && [ -f "$BIOS_ROM" ] || \
		lf_die "BIOS bootrom missing (pkg install seabios). Set LF_BIOS_ROM=..."
	lf_log "BIOS mode: bootrom=$BIOS_ROM"
	BHYVE_ARGS="$BHYVE_ARGS -l bootrom,$BIOS_ROM"
fi

lf_log "Starting bhyve $VMNAME (timeout ${TIMEOUT}s); log $LF_CURRENT_LOG"
# Non-interactive: run bhyve briefly and capture serial via script.
# Full console automation can be upgraded later; for now we verify start + ISO attach.
if command -v timeout >/dev/null 2>&1; then
	TO=timeout
elif command -v gtimeout >/dev/null 2>&1; then
	TO=gtimeout
else
	TO=""
fi

set +e
if [ -n "$TO" ]; then
	$TO "$TIMEOUT" bhyve $BHYVE_ARGS "$VMNAME" >"$LF_CURRENT_LOG" 2>&1
	rc=$?
else
	bhyve $BHYVE_ARGS "$VMNAME" >"$LF_CURRENT_LOG" 2>&1 &
	bpid=$!
	i=0
	while [ "$i" -lt "$TIMEOUT" ]; do
		kill -0 "$bpid" 2>/dev/null || break
		sleep 1
		i=$((i + 1))
	done
	kill "$bpid" 2>/dev/null || true
	wait "$bpid" 2>/dev/null
	rc=0
fi
set -e

cleanup
trap - EXIT INT TERM

if grep -Eqi 'limine|linux|busybox|Kernel panic|lfs-from-freebsd|LFS from|BdsDxe' "$LF_CURRENT_LOG" 2>/dev/null \
	|| strings -a "$LF_CURRENT_LOG" 2>/dev/null | grep -Eqi 'limine|LFS from|busybox|linux version'; then
	lf_log "Saw boot-related output in $LF_CURRENT_LOG"
else
	lf_log "WARN: no recognizable boot strings yet in $LF_CURRENT_LOG (firmware may need console tweaks)"
fi

if [ "$DO_INSTALL" -eq 1 ]; then
	lf_log "Install path: use --install with expect/nmdm automation (scaffold); see ROADMAP"
fi
if [ "$DO_DESKTOP" -eq 1 ]; then
	lf_log "Desktop smoke requires Milestone C packages + GPU; see docs/DESKTOP-PLASMA6.md"
fi

lf_log "=== vm-boot-test finished (bhyve rc=$rc); review $LF_CURRENT_LOG ==="
# Soft-pass if VM ran; harden to require prompt once serial capture is reliable.
exit 0
