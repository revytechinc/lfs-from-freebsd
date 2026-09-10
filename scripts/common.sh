#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# common.sh — shared helpers for lfs-from-freebsd scripts.
#
# WHAT: Locate repo root, load versions.env, logging, checksum verify, jobs.
# WHY:  Every script must agree on paths and pins; do not re-implement.
# HOST: FreeBSD (primary). Some helpers are POSIX enough for the Linux guest.
# OUT:  None (sourced only).

# Prevent double-source issues
if [ -n "${LF_COMMON_LOADED:-}" ]; then
	return 0 2>/dev/null || exit 0
fi
LF_COMMON_LOADED=1

# Always derive LF_ROOT from this script's path (ignore poisoned LF_ROOT).
_lf_common="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
case "$_lf_common" in
*/scripts/builder-guest) LF_ROOT="$(CDPATH= cd -- "$_lf_common/../.." && pwd)" ;;
*/scripts) LF_ROOT="$(CDPATH= cd -- "$_lf_common/.." && pwd)" ;;
*) LF_ROOT="$(CDPATH= cd -- "$_lf_common/.." && pwd)" ;;
esac
export LF_ROOT

LF_VENDOR="${LF_ROOT}/vendor"
LF_OUT="${LF_ROOT}/out"
LF_LOGDIR="${LF_OUT}/logs"
export LF_VENDOR LF_OUT LF_LOGDIR

# shellcheck disable=SC1091
. "$LF_ROOT/versions.env"

# Absolute path — never trust PATH (linuxulator binutils dirs must not shadow this).
lf_uname="$(/usr/bin/uname -s 2>/dev/null || uname -s)"
export lf_uname

lf_jobs() {
	if [ -n "${LF_JOBS:-}" ]; then
		echo "$LF_JOBS"
		return
	fi
	case "$lf_uname" in
	FreeBSD) sysctl -n hw.ncpu 2>/dev/null || echo 4 ;;
	Linux) nproc 2>/dev/null || echo 4 ;;
	*) echo 4 ;;
	esac
}

lf_log() {
	printf '%s\n' "$*" >&2
}

lf_die() {
	lf_log "ERROR: $*"
	exit 1
}

lf_need_freebsd() {
	[ "$lf_uname" = "FreeBSD" ] || lf_die "This step must run on FreeBSD (got $lf_uname). See docs/BUILD-HOST.md"
}

lf_mkdirs() {
	mkdir -p "$LF_VENDOR" "$LF_OUT" "$LF_LOGDIR" \
		"$LF_OUT/linux" "$LF_OUT/initramfs" "$LF_OUT/rootfs" \
		"$LF_OUT/zfs" "$LF_OUT/iso" "$LF_OUT/builder" "$LF_OUT/images"
}

lf_timestamp() {
	date -u +%Y%m%dT%H%M%SZ
}

lf_logfile() {
	_name="$1"
	lf_mkdirs
	echo "$LF_LOGDIR/${_name}-$(lf_timestamp).log"
}

# lf_sha256 FILE → print hex digest
lf_sha256() {
	if command -v sha256 >/dev/null 2>&1; then
		# FreeBSD
		sha256 -q "$1"
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		lf_die "no sha256 tool found"
	fi
}

# lf_verify FILE EXPECTED_SHA256
# Empty expected is only allowed for non-executed metadata (wget-list).
# Use lf_verify_required for anything that will be executed or booted.
lf_verify() {
	_file="$1"
	_expect="$2"
	[ -f "$_file" ] || lf_die "missing file: $_file"
	if [ -z "$_expect" ]; then
		_got="$(lf_sha256 "$_file")"
		lf_log "WARN: no pinned SHA256 for $_file; got $_got — record it in versions.env"
		return 0
	fi
	_got="$(lf_sha256 "$_file")"
	[ "$_got" = "$_expect" ] || lf_die "SHA256 mismatch for $_file: expected $_expect got $_got"
	lf_log "OK sha256 $_file"
}

# lf_verify_required FILE EXPECTED_SHA256 — empty digest is a hard error
lf_verify_required() {
	_file="$1"
	_expect="$2"
	[ -n "$_expect" ] || lf_die "refusing $_file: pinned SHA256 is empty (versions.env)"
	lf_verify "$_file" "$_expect"
}

# lf_fetch URL DEST SHA256
lf_fetch() {
	_url="$1"
	_dest="$2"
	_sha="$3"
	lf_mkdirs
	if [ -f "$_dest" ]; then
		if [ -n "$_sha" ] && [ "$(lf_sha256 "$_dest")" = "$_sha" ]; then
			lf_log "cached $_dest"
			return 0
		fi
		lf_log "re-fetching $_dest (cache miss or hash mismatch)"
		rm -f "$_dest"
	fi
	lf_log "fetch $_url → $_dest"
	curl -fL --retry 3 --retry-delay 2 -o "$_dest" "$_url" || lf_die "download failed: $_url"
	lf_verify "$_dest" "$_sha"
}

lf_clang() {
	if [ -n "${LF_CLANG:-}" ]; then
		echo "$LF_CLANG"
		return
	fi
	for c in clang19 clang18 clang17 clang; do
		if command -v "$c" >/dev/null 2>&1; then
			echo "$c"
			return
		fi
	done
	lf_die "no clang found; install llvm or base clang"
}

# lf_start_log NAME — tee to out/logs without bash process substitution
# FreeBSD /bin/sh has no >( ). Caller should not rely on stdout after this
# for interactive use; long builds get a file log + mirrored stdout via tee
# started in the background pipeline when available, else plain redirect.
lf_start_log() {
	_lf_logf="$(lf_logfile "$1")"
	export LF_CURRENT_LOG="$_lf_logf"
	lf_log "logging to $_lf_logf"
	# Prefer `tee` via named pipe when possible; simplest portable: duplicate with tee if
	# the shell supports it. Fallback: redirect only to the log file and print path.
	if (echo test | tee /dev/null >/dev/null) 2>/dev/null; then
		# Open FD 3 as a copy of stdout, then pipe through tee.
		exec 3>&1
		exec >"$_lf_logf" 2>&1
		# Note: simultaneous console+file without process subst: use script(1) later.
		# For now log file is authoritative; echo path to fd3.
		echo "log=$_lf_logf" >&3
	else
		exec >"$_lf_logf" 2>&1
	fi
}

# lf_allow_abs_path PATH — absolute, no .., no empty segments, safe charset
lf_allow_abs_path() {
	_p="$1"
	case "$_p" in
	/*) ;;
	*) return 1 ;;
	esac
	case "$_p" in
	*..*) return 1 ;;
	esac
	printf '%s' "$_p" | grep -Eq '^/[A-Za-z0-9._/-]+$' || return 1
	printf '%s' "$_p" | grep -Eq '//' && return 1
	return 0
}

# lf_allow_ssh_target USER@HOST — reject option-like targets
lf_allow_ssh_target() {
	_t="$1"
	case "$_t" in
	-*) return 1 ;;
	*@*) printf '%s' "$_t" | grep -Eq '^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$' || return 1 ;;
	*) return 1 ;;
	esac
	return 0
}
