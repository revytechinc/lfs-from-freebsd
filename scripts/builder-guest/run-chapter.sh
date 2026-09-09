#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# builder-guest/run-chapter.sh — scp + ssh a chapters/*.sh into the guest.
set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/common.sh"
lf_need_freebsd
CHAPTER="${1:?usage: run-chapter.sh chapters/NNNN-name.sh}"
[ -f "$LF_OUT/builder/state.env" ] || lf_die "missing builder state"
# shellcheck disable=SC1091
. "$LF_OUT/builder/state.env"
[ -n "${BUILDER_SSH:-}" ] || lf_die "Set BUILDER_SSH=user@host in out/builder/state.env"
lf_allow_ssh_target "$BUILDER_SSH" || lf_die "BUILDER_SSH rejected: $BUILDER_SSH"

LFS_REMOTE="${LFS_REMOTE:-/lfs}"
STATE_REMOTE="${LF_CHAPTER_STATE_REMOTE:-/var/tmp/lfs-chapters}"
lf_allow_abs_path "$LFS_REMOTE" || lf_die "LFS_REMOTE rejected: $LFS_REMOTE"
lf_allow_abs_path "$STATE_REMOTE" || lf_die "STATE_REMOTE rejected: $STATE_REMOTE"

scp -- "$CHAPTER" "$BUILDER_SSH:/var/tmp/lfs-chapter.$$.sh"
ssh -- "$BUILDER_SSH" env "LFS=$LFS_REMOTE" "LF_CHAPTER_STATE=$STATE_REMOTE" \
	LF_OVERLAY_INSTALLED=/var/tmp/lfs-overlay-installed \
	CHAPTER_SCRIPT="/var/tmp/lfs-chapter.$$.sh" \
	sh -c 'mkdir -p "$LFS" "$LF_CHAPTER_STATE" && sh "$CHAPTER_SCRIPT" && rm -f "$CHAPTER_SCRIPT"'
lf_log "chapter $CHAPTER completed on builder"
