#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# builder-guest/run-next-chapter.sh — run the lowest-numbered pending chapter.
set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/common.sh"
lf_need_freebsd

DONE="$LF_OUT/builder/chapters.done"
mkdir -p "$LF_OUT/builder"
touch "$DONE"

for ch in "$LF_ROOT"/chapters/[0-9][0-9][0-9][0-9]-*.sh; do
	[ -f "$ch" ] || continue
	base="$(basename "$ch")"
	id="${base%%-*}"
	if grep -qx "$id" "$DONE" 2>/dev/null; then
		continue
	fi
	lf_log "Running next chapter: $base"
	"$LF_ROOT/scripts/builder-guest/run-chapter.sh" "$ch"
	echo "$id" >> "$DONE"
	exit 0
done
lf_log "No pending chapters"
