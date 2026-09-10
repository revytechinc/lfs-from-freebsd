#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# build-linux-kernel-via-builder.sh — hybrid fallback when FreeBSD host
# kbuild cannot finish (objtool / asm headers). Boots Alpine under bhyve
# briefly is heavy; this script instead prepares a self-contained build
# script and documents the preferred path.
#
# Preferred automated path on FreeBSD: use linuxulator (linux_base) if
# present — see try_linuxulator_build().
#
# DOCS: docs/KERNEL-FROM-FREEBSD.md, docs/BUILDER-GUEST.md

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

try_linuxulator_build() {
	LINUXROOT="${LF_LINUX_ROOT:-/compat/linux}"
	if [ ! -x "$LINUXROOT/bin/bash" ] && [ ! -x "$LINUXROOT/usr/bin/bash" ]; then
		return 1
	fi
	lf_log "Attempting kernel build via linuxulator at $LINUXROOT"
	# Mount and chroot build is environment-specific; stage a script the
	# operator (or fleet tool) can run inside the Linux ABI jail.
	cat > "$LF_OUT/linux/build-in-linux.sh" <<'EOS'
#!/bin/bash
set -euo pipefail
# Run under Linux (linuxulator chroot or builder guest).
: "${LFS_LINUX_SRC:?}"
: "${LFS_LINUX_OUT:?}"
cd "$LFS_LINUX_SRC"
make O="$LFS_LINUX_OUT" ARCH=x86_64 defconfig
# Apply fragment via scripts/config if present
make O="$LFS_LINUX_OUT" ARCH=x86_64 -j"$(nproc)" bzImage modules
EOS
	chmod +x "$LF_OUT/linux/build-in-linux.sh"
	lf_log "Wrote $LF_OUT/linux/build-in-linux.sh — run inside Linux ABI"
	return 0
}

lf_log "=== hybrid kernel fallback ==="
try_linuxulator_build || lf_log "linuxulator not ready — use make builder + guest kernel build"
lf_log "See docs/KERNEL-FROM-FREEBSD.md"
