#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# run-chapter-freebsd.sh — run chapters/*.sh on FreeBSD against out/sysroot.
#
# WHAT: Export LFS DESTDIR + FreeBSD cross PATH; execute one chapter script.
# WHY:  Path of record — no Alpine SSH builder (docs/ARCHITECTURE.md).
# HOST: FreeBSD only.
# OUT:  out/lfs/ (LFS), out/chapters/<id>.done, out/logs/
# DOCS: docs/FREEBSD-CROSS-USERSPACE.md
set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

CHAPTER="${1:?usage: run-chapter-freebsd.sh chapters/NNNN-name.sh}"
case "$CHAPTER" in
/*) ;;
*) CHAPTER="$LF_ROOT/$CHAPTER" ;;
esac
[ -f "$CHAPTER" ] || lf_die "missing chapter: $CHAPTER"
CHAPTER="$(realpath -q "$CHAPTER" 2>/dev/null || true)"
[ -n "$CHAPTER" ] || lf_die "cannot resolve chapter path"
case "$CHAPTER" in
"$LF_ROOT"/chapters/*.sh) ;;
*) lf_die "chapter must resolve under $LF_ROOT/chapters/ (got $CHAPTER)" ;;
esac
[ -f "$CHAPTER" ] || lf_die "missing chapter: $CHAPTER"
base=$(basename "$CHAPTER" .sh)
printf '%s' "$base" | grep -Eq '^[0-9A-Za-z._-]+$' || lf_die "refusing chapter basename $base"
# Chapter id is derived from the filename only (not overridable).
LF_CHAPTER_ID="${base%%-*}"
printf '%s' "$LF_CHAPTER_ID" | grep -Eq '^[0-9][0-9A-Za-z._-]*$' || \
	lf_die "refusing LF_CHAPTER_ID=$LF_CHAPTER_ID"
case "$LF_CHAPTER_ID" in
*..*) lf_die "refusing LF_CHAPTER_ID with .." ;;
esac
export LF_CHAPTER_ID

# shellcheck disable=SC1091
[ -f "$LF_OUT/toolchain/env.sh" ] || lf_die "missing out/toolchain/env.sh (gmake toolchain)"
. "$LF_OUT/toolchain/env.sh"

SYSROOT="${LF_SYSROOT:-$LF_OUT/sysroot}"
case "$SYSROOT" in
*".."*) lf_die "SYSROOT must not contain .." ;;
"$LF_OUT"/*) ;;
*) lf_die "SYSROOT must be under $LF_OUT (got $SYSROOT)" ;;
esac
[ -d "$SYSROOT" ] || lf_die "missing sysroot — gmake spike-sysroot first"
lf_path_under "$SYSROOT" "$LF_OUT"
[ -d "$SYSROOT/usr/include" ] || lf_die "missing sysroot — gmake spike-sysroot first"
# Non-empty libc (empty/stale files must not skip wrappers).
if [ ! -s "$SYSROOT/usr/lib/libc.a" ] && [ ! -s "$SYSROOT/usr/lib/libc.so" ]; then
	lf_die "sysroot has no libc — gmake spike-sysroot first"
fi
MUSL_LD_NAME="$(lf_musl_ld_name)"
_ld="$SYSROOT/lib/$MUSL_LD_NAME"
[ -e "$_ld" ] || lf_die "missing musl dynamic linker $_ld — gmake sysroot"
_ld_real="$(realpath -q "$_ld" 2>/dev/null || true)"
[ -n "$_ld_real" ] && [ -s "$_ld_real" ] || \
	lf_die "broken musl dynamic linker $_ld — gmake sysroot"

# Stage libgcc stubs + wrappers if not already present.
if [ ! -s "$SYSROOT/usr/lib/libgcc.a" ]; then
	"$LF_ROOT/scripts/stage-linux-libgcc-stubs.sh"
fi
if [ ! -x "$LF_OUT/toolchain/bin/${TARGET_TRIPLE:-x86_64-linux-gnu}-gcc" ]; then
	"$LF_ROOT/scripts/install-cross-wrappers.sh"
fi
# shellcheck disable=SC1091
[ -f "$LF_OUT/toolchain/wrappers.env" ] || lf_die "missing wrappers.env — gmake wrappers"
. "$LF_OUT/toolchain/wrappers.env"

export LF_OUT="$LF_OUT"
export LF_ROOT="$LF_ROOT"
export LF_VENDOR="$LF_VENDOR"
export LF_SYSROOT="$SYSROOT"
# Fresh FreeBSD DESTDIR — never Alpine out/destdir; path of record is out/lfs.
# Build/state dirs are forced (no env override) to avoid out/ symlink escapes.
export LFS="$LF_OUT/lfs"
export LF_BUILD_ROOT="$LF_OUT/build/chapters"
export LF_CHAPTER_STATE="$LF_OUT/chapters"
mkdir -p "$LFS" "$LF_BUILD_ROOT" "$LF_CHAPTER_STATE"
lf_path_under "$LFS" "$LF_OUT"
lf_path_under "$LF_BUILD_ROOT" "$LF_OUT"
lf_path_under "$LF_CHAPTER_STATE" "$LF_OUT"
export LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
export LF_JOBS="${LF_JOBS:-$(lf_jobs)}"
export PATH="$LF_OUT/toolchain/bin:${PATH:-}"

# Chapters that still expect tools under $LFS/tools (Alpine temporary toolchain)
# get a symlink farm to FreeBSD clang wrappers.
mkdir -p "$LFS/tools/bin"
for w in "$LF_OUT/toolchain/bin/${LFS_TGT}"-*; do
	[ -e "$w" ] || continue
	base=$(basename "$w")
	ln -sfn "$w" "$LFS/tools/bin/$base"
done
# Also expose TARGET_TRIPLE-prefixed names when chapters use that.
for w in "$LF_OUT/toolchain/bin/${TARGET_TRIPLE:-x86_64-linux-gnu}"-*; do
	[ -e "$w" ] || continue
	base=$(basename "$w")
	ln -sfn "$w" "$LFS/tools/bin/$base"
done

lf_start_log "chapter-${LF_CHAPTER_ID}"
lf_log "=== FreeBSD chapter $CHAPTER (LFS=$LFS sysroot=$SYSROOT) ==="
sh "$CHAPTER"
touch "$LF_CHAPTER_STATE/${LF_CHAPTER_ID}.done"
lf_log "=== chapter ${LF_CHAPTER_ID} OK ==="
