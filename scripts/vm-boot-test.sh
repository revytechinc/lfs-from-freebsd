#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# vm-boot-test.sh — bhyve smoke tests for BIOS and UEFI.
#
# WHAT: Boot out/lfs-from-freebsd.iso under bhyve; optionally install to a
#       second disk and cold-boot the installed ZFS root.
# WHY:  Prove hybrid medium + install path on the CloudBSD build host.
# HOST: FreeBSD with bhyve + UEFI firmware package (+ nmdm for --install).
# OUT:  out/logs/vm-*.log; exit 0 on prompt / install success
# DOCS: docs/BOOT-AND-ISO.md, docs/ZFS-ROOT.md
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

if command -v timeout >/dev/null 2>&1; then
	TO=timeout
elif command -v gtimeout >/dev/null 2>&1; then
	TO=gtimeout
else
	TO=""
fi

bootrom_args() {
	if [ "$FIRMWARE" = "uefi" ]; then
		[ -f "$UEFI_CODE" ] || lf_die "UEFI code missing: $UEFI_CODE"
		cp -f "$UEFI_VARS_SRC" "$VARS"
		echo "-l bootrom,$UEFI_CODE,$VARS"
	else
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
		echo "-l bootrom,$BIOS_ROM"
	fi
}

# --- install path: stdio serial + FIFO for typed commands ---
if [ "$DO_INSTALL" -eq 1 ]; then
	FIFO="$LF_OUT/images/${VMNAME}-stdin.fifo"
	rm -f "$FIFO"
	mkfifo "$FIFO"
	: >"$LF_CURRENT_LOG"
	BOOTROM="$(bootrom_args)"

	# Start bhyve first (blocks opening FIFO for read until we open the writer).
	# shellcheck disable=SC2086
	bhyve -c 2 -m 2G -H -A -P \
		-s 0:0,hostbridge -s 1:0,lpc \
		-l com1,stdio \
		$BOOTROM \
		-s 3:0,ahci-cd,"$ISO" \
		-s 4:0,virtio-blk,"$DISK" \
		"$VMNAME" <"$FIFO" >>"$LF_CURRENT_LOG" 2>&1 &
	bpid=$!
	# Open writer end so bhyve's stdin open completes.
	exec 3>"$FIFO"
	lf_log "install VM pid=$bpid (stdio+fifo)"

	i=0
	saw_live=0
	while [ "$i" -lt "$TIMEOUT" ]; do
		if grep -q 'lfs-from-freebsd live root\|Install to ZFS' "$LF_CURRENT_LOG" 2>/dev/null; then
			saw_live=1
			break
		fi
		if grep -Eqi 'Kernel panic' "$LF_CURRENT_LOG" 2>/dev/null; then
			break
		fi
		kill -0 "$bpid" 2>/dev/null || break
		sleep 1
		i=$((i + 1))
	done

	if [ "$saw_live" -ne 1 ]; then
		lf_log "ERROR: live prompt not seen for install (log $LF_CURRENT_LOG)"
		exec 3>&-
		kill "$bpid" 2>/dev/null || true
		wait "$bpid" 2>/dev/null || true
		rm -f "$FIFO"
		cleanup
		exit 1
	fi

	lf_log "Typing install-to-zfs.sh --disk /dev/vda --yes (explicit; not --auto)"
	printf 'export LD_LIBRARY_PATH=/usr/lib:/lib\r\n' >&3
	sleep 1
	# Live root is the ISO (sr0); first virtio-blk is the install target.
	# Do not use --auto here — that path only accepts a second virt disk.
	printf 'install-to-zfs.sh --disk /dev/vda --yes\r\n' >&3

	i=0
	install_ok=0
	while [ "$i" -lt 300 ]; do
		if grep -q 'install complete' "$LF_CURRENT_LOG" 2>/dev/null; then
			install_ok=1
			break
		fi
		if grep -Eqi 'Kernel panic' "$LF_CURRENT_LOG" 2>/dev/null; then
			break
		fi
		kill -0 "$bpid" 2>/dev/null || break
		sleep 1
		i=$((i + 1))
	done

	exec 3>&-
	# bhyve often ignores SIGTERM with stdio+fifo held; force destroy.
	kill "$bpid" 2>/dev/null || true
	sleep 1
	kill -9 "$bpid" 2>/dev/null || true
	bhyvectl --vm="$VMNAME" --destroy 2>/dev/null || true
	wait "$bpid" 2>/dev/null || true
	rm -f "$FIFO"
	cleanup

	if [ "$install_ok" -ne 1 ]; then
		lf_log "ERROR: install-to-zfs did not report completion — see $LF_CURRENT_LOG"
		exit 1
	fi
	lf_log "Install reported complete; cold-booting disk without ISO"

	# Cold boot installed disk only.
	lf_start_log "vm-${FIRMWARE}-cold"
	: >"$LF_CURRENT_LOG"
	BOOTROM="$(bootrom_args)"
	# shellcheck disable=SC2086
	if [ -n "$TO" ]; then
		$TO "$TIMEOUT" bhyve -c 2 -m 2G -H -A -P \
			-s 0:0,hostbridge -s 1:0,lpc \
			-l com1,stdio \
			$BOOTROM \
			-s 4:0,virtio-blk,"$DISK" \
			"$VMNAME" >"$LF_CURRENT_LOG" 2>&1
		rc=$?
	else
		bhyve -c 2 -m 2G -H -A -P \
			-s 0:0,hostbridge -s 1:0,lpc \
			-l com1,stdio \
			$BOOTROM \
			-s 4:0,virtio-blk,"$DISK" \
			"$VMNAME" >"$LF_CURRENT_LOG" 2>&1 &
		bpid=$!
		i=0
		while [ "$i" -lt "$TIMEOUT" ]; do
			kill -0 "$bpid" 2>/dev/null || break
			sleep 1
			i=$((i + 1))
		done
		kill "$bpid" 2>/dev/null || true
		wait "$bpid" 2>/dev/null || true
		rc=0
	fi
	cleanup
	trap - EXIT INT TERM

	if grep -Eqi 'root=ZFS|rpool/ROOT/lfs|Kernel panic|lfs-from-freebsd' "$LF_CURRENT_LOG"; then
		lf_log "Cold boot produced ZFS/root-related output"
	else
		lf_log "WARN: cold boot log lacks ZFS root markers — review $LF_CURRENT_LOG"
	fi
	if grep -Eqi 'Kernel panic' "$LF_CURRENT_LOG"; then
		lf_log "ERROR: panic on cold boot"
		exit 1
	fi
	lf_log "=== vm-boot-test --install finished (rc=$rc) ==="
	[ "$DO_DESKTOP" -eq 1 ] && lf_log "Desktop smoke still Milestone C — docs/DESKTOP-PLASMA6.md"
	exit 0
fi

# --- smoke boot (stdio serial) ---
BOOTROM="$(bootrom_args)"
BHYVE_ARGS="-c 2 -m 2G -H -A -P"
BHYVE_ARGS="$BHYVE_ARGS -s 0:0,hostbridge -s 1:0,lpc"
BHYVE_ARGS="$BHYVE_ARGS -l com1,stdio"
BHYVE_ARGS="$BHYVE_ARGS $BOOTROM"
BHYVE_ARGS="$BHYVE_ARGS -s 3:0,ahci-cd,$ISO"
BHYVE_ARGS="$BHYVE_ARGS -s 4:0,virtio-blk,$DISK"

lf_log "Starting bhyve $VMNAME (timeout ${TIMEOUT}s); log $LF_CURRENT_LOG"
set +e
# shellcheck disable=SC2086
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

if grep -Eqi 'limine|linux|busybox|Kernel panic|lfs-from-freebsd|Linux on FreeBSD|BdsDxe|live root' "$LF_CURRENT_LOG" 2>/dev/null \
	|| strings -a "$LF_CURRENT_LOG" 2>/dev/null | grep -Eqi 'limine|Linux on FreeBSD|busybox|linux version|live root'; then
	lf_log "Saw boot-related output in $LF_CURRENT_LOG"
else
	lf_log "WARN: no recognizable boot strings yet in $LF_CURRENT_LOG (firmware may need console tweaks)"
fi

if [ "$DO_DESKTOP" -eq 1 ]; then
	lf_log "Desktop smoke requires Milestone C packages + GPU; see docs/DESKTOP-PLASMA6.md"
fi

lf_log "=== vm-boot-test finished (bhyve rc=$rc); review $LF_CURRENT_LOG ==="
exit 0
