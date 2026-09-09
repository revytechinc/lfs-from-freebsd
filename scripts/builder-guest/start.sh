#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# builder-guest/start.sh — start builder VM under bhyve (UEFI).
# DOCS: docs/BUILDER-GUEST.md
set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/common.sh"
lf_need_freebsd
[ -f "$LF_OUT/builder/state.env" ] || lf_die "run create.sh first"
# shellcheck disable=SC1091
. "$LF_OUT/builder/state.env"

UEFI_CODE="${LF_UEFI_CODE:-/usr/local/share/uefi-firmware/BHYVE_UEFI_CODE.fd}"
UEFI_VARS_SRC="${LF_UEFI_VARS:-/usr/local/share/uefi-firmware/BHYVE_UEFI_VARS.fd}"
VARS="$LF_OUT/builder/vars.fd"
cp -f "$UEFI_VARS_SRC" "$VARS"

bhyvectl --vm="$BUILDER_VM_NAME" --destroy 2>/dev/null || true

lf_log "Starting builder $BUILDER_VM_NAME (manual Alpine install first boot if needed)"
lf_log "Attach serial and install openssh; then set BUILDER_SSH in state.env"
# Launch in background for operator; full cloud-init automation is follow-up work.
bhyve -c "$BUILDER_CPUS" -m "${BUILDER_MEM_MB}M" -H -A -P \
	-s 0:0,hostbridge -s 1:0,lpc -l com1,stdio \
	-l bootrom,"$UEFI_CODE","$VARS" \
	-s 3:0,ahci-cd,"$BUILDER_ISO" \
	-s 4:0,virtio-blk,"$BUILDER_DISK" \
	"$BUILDER_VM_NAME" || true

lf_log "Builder session ended; update BUILDER_SSH when sshd is up"
