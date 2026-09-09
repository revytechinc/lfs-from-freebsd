#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/1500-desktop-overlay.sh — merge overlays/installed desktop bits.
set -eu
: "${LFS:?}"; : "${LF_CHAPTER_ID:=1500}"
OVERLAY="${LF_OVERLAY_INSTALLED:?set LF_OVERLAY_INSTALLED to overlays/installed tree}"

echo "=== chapter ${LF_CHAPTER_ID}: merge installed desktop overlay ==="
if [ ! -d "$OVERLAY" ]; then
	echo "ERROR: overlay missing: $OVERLAY" >&2
	exit 1
fi
TMPARC=$(mktemp /tmp/lfs-overlay.XXXXXX) || exit 1
trap 'rm -f "$TMPARC"' EXIT
( cd "$OVERLAY" && tar cf "$TMPARC" . )
( cd "$LFS" && tar xpf "$TMPARC" )
rm -f "$TMPARC"
trap - EXIT
mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
