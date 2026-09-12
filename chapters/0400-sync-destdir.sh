#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0400-sync-destdir.sh — record DESTDIR sync marker for FreeBSD host.
# The DESTDIR lives on the 9p share (out/destdir); FreeBSD already sees it.
# This chapter documents a batch boundary for snapshots / install rebuilds.
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0400}"

echo "=== chapter ${LF_CHAPTER_ID}: sync DESTDIR marker ==="
[ -d "$LFS/usr" ] || {
	echo "DESTDIR looks empty: $LFS" >&2
	exit 1
}
mkdir -p "$LFS/var/lib/lfs-from-freebsd"
date -u +"synced=%Y-%m-%dT%H:%M:%SZ" >"$LFS/var/lib/lfs-from-freebsd/destdir-sync.txt"
# Count a few key artifacts for the FreeBSD-side log.
{
	echo "LFS=$LFS"
	ls -la "$LFS/tools/bin" 2>/dev/null | wc -l | awk '{print "tools_bin_entries="$1}'
	ls "$LFS/usr/lib/libc.so.6" "$LFS/lib/libc.so.6" 2>/dev/null | head -2 || true
	test -x "$LFS/usr/bin/gcc" && echo "usr_bin_gcc=yes" || echo "usr_bin_gcc=no"
} | tee -a "$LFS/var/lib/lfs-from-freebsd/destdir-sync.txt"

mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
