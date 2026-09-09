#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0000-host-prep.sh — first LFS chapter (runs IN the Linux builder).
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0000}"

echo "=== chapter ${LF_CHAPTER_ID}: host prep ==="
# Explicit mkdir list — no bash brace expansion (Alpine ash is POSIX).
mkdir -p "$LFS/etc" "$LFS/bin" "$LFS/lib" "$LFS/lib64" "$LFS/sbin" \
	"$LFS/usr" "$LFS/var" "$LFS/tools" "$LFS/boot" "$LFS/dev" "$LFS/proc" \
	"$LFS/sys" "$LFS/run" "$LFS/tmp" "$LFS/home" "$LFS/root" "$LFS/media" \
	"$LFS/mnt" "$LFS/opt" "$LFS/srv"
mkdir -p "$LFS/usr/bin" "$LFS/usr/lib" "$LFS/usr/lib64" "$LFS/usr/sbin" \
	"$LFS/usr/share" "$LFS/usr/include"
mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
