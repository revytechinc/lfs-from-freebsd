#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/1600-desktop-smoke.sh — file-level checks for overlay presence.
# Full greeter proof is make test-desktop on FreeBSD (bhyve).
set -eu
: "${LFS:?}"; : "${LF_CHAPTER_ID:=1600}"
echo "=== chapter ${LF_CHAPTER_ID}: desktop smoke (file-level) ==="
missing=0
for f in \
	etc/sddm.conf.d/10-lfs.conf \
	usr/share/wayland-sessions/plasmawayland.desktop \
	etc/lfs-from-freebsd/desktop.conf \
	etc/lfs-from-freebsd/open-vm-tools.required
do
	if [ ! -e "$LFS/$f" ]; then
		echo "MISSING: $LFS/$f" >&2
		missing=1
	else
		echo "OK $f"
	fi
done
# Under VMware, vmtoolsd must exist once chapter 1450 has run.
if [ -x "$LFS/usr/bin/vmtoolsd" ] || [ -x "$LFS/usr/sbin/vmtoolsd" ]; then
	echo "OK vmtoolsd binary (VMware guest tools)"
else
	echo "NOTE: vmtoolsd not in DESTDIR yet — chapter 1450 still pending"
fi
[ "$missing" -eq 0 ] || exit 1
mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="
