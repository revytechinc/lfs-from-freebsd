#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# builder-guest/start.sh — start Alpine builder under bhyve (UEFI).
#
# WHAT: Boot BUILDER_ISO + BUILDER_DISK with virtio-9p share of the repo out/
#       and vendor/ trees so the guest can build OpenZFS without linuxulator.
# WHY:  Pure FreeBSD host; real Linux VM for OpenZFS / LFS chapters.
# HOST: FreeBSD with bhyve + UEFI firmware. Needs doas for bhyve.
# DOCS: docs/BUILDER-GUEST.md
#
# Usage:
#   doas ./scripts/builder-guest/start.sh           # foreground serial
#   doas ./scripts/builder-guest/start.sh --daemon  # background; log under out/logs/

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/common.sh"
lf_need_freebsd
[ -f "$LF_OUT/builder/state.env" ] || lf_die "run create.sh first"
# shellcheck disable=SC1091
. "$LF_OUT/builder/state.env"

DAEMON=0
[ "${1:-}" = "--daemon" ] && DAEMON=1

UEFI_CODE="${LF_UEFI_CODE:-/usr/local/share/uefi-firmware/BHYVE_UEFI_CODE.fd}"
UEFI_VARS_SRC="${LF_UEFI_VARS:-/usr/local/share/uefi-firmware/BHYVE_UEFI_VARS.fd}"
VARS="$LF_OUT/builder/vars.fd"
cp -f "$UEFI_VARS_SRC" "$VARS"

# Share FreeBSD-built trees into the guest (OpenZFS builds against these).
SHARE_DIR="$LF_OUT/builder/share"
mkdir -p "$SHARE_DIR"
# Stable paths the guest answerfile / scripts expect
ln -sfn "$LF_OUT" "$SHARE_DIR/out"
ln -sfn "$LF_VENDOR" "$SHARE_DIR/vendor"
ln -sfn "$LF_ROOT/scripts" "$SHARE_DIR/scripts"
cp -f "$LF_ROOT/scripts/builder-guest/alpine-answers" "$SHARE_DIR/alpine-answers" 2>/dev/null || true
cp -f "$LF_ROOT/scripts/builder-guest/guest-build-openzfs.sh" "$SHARE_DIR/guest-build-openzfs.sh" 2>/dev/null || true

bhyvectl --vm="$BUILDER_VM_NAME" --destroy 2>/dev/null || true

BHYVE_ARGS="-c $BUILDER_CPUS -m ${BUILDER_MEM_MB}M -H -A -P"
BHYVE_ARGS="$BHYVE_ARGS -s 0:0,hostbridge -s 1:0,lpc"
BHYVE_ARGS="$BHYVE_ARGS -l com1,stdio"
BHYVE_ARGS="$BHYVE_ARGS -l bootrom,$UEFI_CODE,$VARS"
BHYVE_ARGS="$BHYVE_ARGS -s 3:0,ahci-cd,$BUILDER_ISO"
BHYVE_ARGS="$BHYVE_ARGS -s 4:0,virtio-blk,$BUILDER_DISK"
# Host directory share — mount in guest: mount -t 9p -o trans=virtio lfs /mnt/lfs
BHYVE_ARGS="$BHYVE_ARGS -s 5:0,virtio-9p,lfs=$SHARE_DIR"

lf_log "Starting builder $BUILDER_VM_NAME (9p share=$SHARE_DIR)"
lf_log "First boot: login as root (live), then:"
lf_log "  mkdir -p /mnt/lfs && mount -t 9p -o trans=virtio lfs /mnt/lfs"
lf_log "  setup-alpine -f /mnt/lfs/alpine-answers"
lf_log "After reboot from disk: /mnt/lfs/guest-build-openzfs.sh"

if [ "$DAEMON" -eq 1 ]; then
	LOG="$(lf_logfile builder-vm)"
	lf_log "Daemon mode — serial log $LOG"
	# shellcheck disable=SC2086
	nohup bhyve $BHYVE_ARGS "$BUILDER_VM_NAME" >"$LOG" 2>&1 &
	echo $! > "$LF_OUT/builder/bhyve.pid"
	lf_log "bhyve pid $(cat "$LF_OUT/builder/bhyve.pid")"
else
	# shellcheck disable=SC2086
	bhyve $BHYVE_ARGS "$BUILDER_VM_NAME" || true
	lf_log "Builder session ended; set BUILDER_SSH in state.env when sshd is up"
fi
