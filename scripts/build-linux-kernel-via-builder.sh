#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# build-linux-kernel-via-builder.sh — NOT the primary path.
#
# Policy: the Linux kernel MUST build on pure FreeBSD (see
# build-linux-kernel.sh and docs/KERNEL-FROM-FREEBSD.md). This script only
# stages a recipe for the real Alpine/bhyve builder if someone is debugging
# a FreeBSD kbuild regression — it does not use linuxulator.
#
# DOCS: docs/KERNEL-FROM-FREEBSD.md, docs/BUILDER-GUEST.md

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

lf_log "=== kernel-via-builder (fallback recipe only) ==="
lf_log "Primary path is pure FreeBSD: gmake kernel"
lf_log "linuxulator is forbidden."

mkdir -p "$LF_OUT/linux"
cat > "$LF_OUT/linux/build-in-builder.sh" <<'EOS'
#!/bin/bash
# Run inside the Alpine/bhyve builder guest — last-resort kernel rebuild.
set -euo pipefail
: "${LFS_LINUX_SRC:?}"
: "${LFS_LINUX_OUT:?}"
cd "$LFS_LINUX_SRC"
make O="$LFS_LINUX_OUT" ARCH=x86_64 defconfig
make O="$LFS_LINUX_OUT" ARCH=x86_64 -j"$(nproc)" bzImage modules
EOS
chmod +x "$LF_OUT/linux/build-in-builder.sh"
lf_log "Wrote $LF_OUT/linux/build-in-builder.sh for builder guest use only"
lf_log "Fix FreeBSD-native gmake kernel instead of relying on this."
