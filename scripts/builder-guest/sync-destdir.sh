#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# builder-guest/sync-destdir.sh — rsync guest /lfs into out/rootfs/lfs
set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/common.sh"
lf_need_freebsd
# shellcheck disable=SC1091
. "$LF_OUT/builder/state.env"
[ -n "${BUILDER_SSH:-}" ] || lf_die "BUILDER_SSH unset"
lf_allow_ssh_target "$BUILDER_SSH" || lf_die "BUILDER_SSH rejected"
# Fixed guest path only — do not honour arbitrary LFS_REMOTE for --delete sync.
LFS_REMOTE=/lfs
DEST="$LF_OUT/rootfs/lfs"
mkdir -p "$DEST"
rsync -aHAX --delete -- "$BUILDER_SSH:$LFS_REMOTE/" "$DEST/"
lf_log "Synced to $DEST"
