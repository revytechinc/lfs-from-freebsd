#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# spike-freebsd-linux-sysroot.sh — FreeBSD-only Linux sysroot spike (musl).
#
# WHAT: Linux UAPI headers + musl into out/sysroot; link a Linux hello ELF.
# WHY:  Prove ARCHITECTURE.md — no Linux VM/jail/linuxulator for userspace.
# HOST: FreeBSD only.
# OUT:  out/sysroot/, out/sysroot/bin/lf-hello, out/logs/spike-sysroot.log
# DOCS: docs/FREEBSD-CROSS-USERSPACE.md
set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

# shellcheck disable=SC1091
. "$LF_ROOT/versions.env"

lf_start_log spike-sysroot
lf_log "=== spike: FreeBSD → Linux sysroot (musl) ==="

SYSROOT="$LF_OUT/sysroot"
BUILD="$LF_OUT/build/spike-sysroot"
TRIPLE="${TARGET_TRIPLE:-x86_64-linux-gnu}"
# clang's Linux target triple spelling
CLANG_TRIPLE="${LF_CLANG_LINUX_TRIPLE:-x86_64-unknown-linux-musl}"

[ -f "$LF_VENDOR/${LINUX_TARBALL}" ] || lf_die "missing vendor/${LINUX_TARBALL} (gmake fetch)"
[ -f "$LF_VENDOR/${MUSL_TARBALL}" ] || lf_die "missing vendor/${MUSL_TARBALL} (gmake fetch)"
lf_verify_required "$LF_VENDOR/${LINUX_TARBALL}" "${LINUX_SHA256:?LINUX_SHA256 unset}"
lf_verify_required "$LF_VENDOR/${MUSL_TARBALL}" "${MUSL_SHA256:?MUSL_SHA256 unset}"

CLANG="$(lf_clang)"
LLD="$(command -v ld.lld || true)"
[ -n "$LLD" ] || lf_die "ld.lld required (pkg install llvm)"

# Refuse path bombs — only delete under this repo's out/.
case "$SYSROOT" in
"$LF_OUT"/*) ;;
*) lf_die "SYSROOT must be under $LF_OUT (got $SYSROOT)" ;;
esac
case "$BUILD" in
"$LF_OUT"/*) ;;
*) lf_die "BUILD must be under $LF_OUT (got $BUILD)" ;;
esac

rm -rf "$SYSROOT" "$BUILD"
mkdir -p "$SYSROOT" "$BUILD"

# --- Linux headers ---
lf_log "--- Linux UAPI headers → $SYSROOT/usr/include ---"
rm -rf "$BUILD/linux"
mkdir -p "$BUILD/linux"
tar -C "$BUILD/linux" --strip-components=1 -xf "$LF_VENDOR/${LINUX_TARBALL}"
(
	cd "$BUILD/linux"
	# Same FreeBSD ELF compat as build-linux-kernel.sh (relocs host tool).
	if [ -f arch/x86/tools/relocs.h ] && \
		! grep -q 'lfs-from-freebsd FreeBSD ELF compat' arch/x86/tools/relocs.h
	then
		awk '
			{ print }
			/#include <elf.h>/ && !done {
				print "#ifdef __FreeBSD__"
				print "/* lfs-from-freebsd FreeBSD ELF compat — docs/KERNEL-FROM-FREEBSD.md */"
				print "#undef ElfW"
				print "#undef ELF_ST_VISIBILITY"
				print "#ifndef R_X86_64_JUMP_SLOT"
				print "#define R_X86_64_JUMP_SLOT R_X86_64_JMP_SLOT"
				print "#endif"
				print "#endif"
				done=1
			}
		' arch/x86/tools/relocs.h > arch/x86/tools/relocs.h.new
		mv arch/x86/tools/relocs.h.new arch/x86/tools/relocs.h
	fi
	# HDRINST recipes need GNU sed (FreeBSD sed rejects the scripts).
	command -v gsed >/dev/null 2>&1 || lf_die "gsed required for Linux headers_install (pkg install gsed)"
	GSED_BIN="$(command -v gsed)"
	mkdir -p "$BUILD/bin"
	ln -sfn "$GSED_BIN" "$BUILD/bin/sed"
	export PATH="$BUILD/bin:$PATH"
	# Do not mrproper after the shim — fresh extract is enough.
	gmake ARCH="${TARGET_ARCH:-x86_64}" headers
	find usr/include -name '.*' -delete
	mkdir -p "$SYSROOT/usr"
	cp -a usr/include "$SYSROOT/usr/"
)

# --- musl ---
lf_log "--- musl ${MUSL_VERSION} cross into sysroot ---"
rm -rf "$BUILD/musl"
mkdir -p "$BUILD/musl"
tar -C "$BUILD/musl" --strip-components=1 -xf "$LF_VENDOR/${MUSL_TARBALL}"
(
	cd "$BUILD/musl"
	# FreeBSD clang targeting Linux; lld as linker; LLVM ar (no $TRIPLE-ar).
	export CC="$CLANG --target=$CLANG_TRIPLE"
	export CFLAGS="-O2 --sysroot=$SYSROOT"
	export LDFLAGS="-fuse-ld=lld --sysroot=$SYSROOT"
	export AR="${LF_LLVM_AR:-$(command -v llvm-ar)}"
	[ -n "$AR" ] || lf_die "llvm-ar required (pkg install llvm)"
	if [ -n "${LF_LLVM_RANLIB:-}" ]; then
		export RANLIB="$LF_LLVM_RANLIB"
		_lf_ranlib_s=0
	elif command -v llvm-ranlib >/dev/null 2>&1; then
		export RANLIB="$(command -v llvm-ranlib)"
		_lf_ranlib_s=0
	else
		# musl's make runs "$(RANLIB) archive"; llvm-ar alone needs "s".
		_ranlib_wrap="$BUILD/ranlib-wrap.sh"
		# Quote AR path for FreeBSD /bin/sh (no printf %q).
		_ar_q=$(printf "'%s'" "$(printf '%s' "$AR" | sed "s/'/'\\''/g")")
		printf '%s\n' '#!/bin/sh' "exec ${_ar_q} s \"\$@\"" >"$_ranlib_wrap"
		chmod 755 "$_ranlib_wrap"
		export RANLIB="$_ranlib_wrap"
		_lf_ranlib_s=1
	fi
	# Do not pass --target= to configure — that prefixes ar as $TRIPLE-ar.
	./configure \
		--prefix=/usr \
		--syslibdir=/lib \
		--disable-wrapper
	# FreeBSD clang ships no on-disk libclang_rt.builtins.a, and configure
	# still records -lgcc. Build minimal Linux-ELF complex helpers musl needs
	# when linking libc.so (__mul{s,d,x}c3).
	STUB_C="$BUILD/compiler-rt-complex-stubs.c"
	STUB_A="$BUILD/libcompiler-rt-stubs.a"
	cat >"$STUB_C" <<'EOF'
/* Minimal compiler-rt helpers for musl shared link (Linux ELF, FreeBSD host). */
float _Complex __mulsc3(float a, float b, float c, float d)
{
	float ac = a * c, bd = b * d, ad = a * d, bc = b * c;
	float _Complex z;
	__real__ z = ac - bd;
	__imag__ z = ad + bc;
	return z;
}
double _Complex __muldc3(double a, double b, double c, double d)
{
	double ac = a * c, bd = b * d, ad = a * d, bc = b * c;
	double _Complex z;
	__real__ z = ac - bd;
	__imag__ z = ad + bc;
	return z;
}
long double _Complex __mulxc3(long double a, long double b, long double c, long double d)
{
	long double ac = a * c, bd = b * d, ad = a * d, bc = b * c;
	long double _Complex z;
	__real__ z = ac - bd;
	__imag__ z = ad + bc;
	return z;
}
EOF
	"$CLANG" --target="$CLANG_TRIPLE" -ffreestanding -fPIC -O2 -c "$STUB_C" -o "$BUILD/compiler-rt-complex-stubs.o"
	"$AR" rc "$STUB_A" "$BUILD/compiler-rt-complex-stubs.o"
	if [ "${_lf_ranlib_s:-0}" = 1 ]; then
		"$AR" s "$STUB_A"
	else
		"$RANLIB" "$STUB_A"
	fi
	if [ -f config.mak ]; then
		awk -v stub="$STUB_A" '
			/^LIBCC[ 	]*=/ { print "LIBCC = " stub; next }
			{ print }
		' config.mak >config.mak.new
		mv config.mak.new config.mak
	fi
	gmake -j"$(lf_jobs)"
	gmake DESTDIR="$SYSROOT" install
)

# Dynamic linker path: musl must install ld-musl-*.so.1 under /lib (do not invent).
MUSL_LD_NAME="$(lf_musl_ld_name)"
[ -s "$SYSROOT/usr/lib/libc.so" ] || \
	lf_die "musl install missing libc.so under $SYSROOT — inspect logs and re-run gmake sysroot"
[ -e "$SYSROOT/lib/$MUSL_LD_NAME" ] || \
	lf_die "musl did not install $SYSROOT/lib/$MUSL_LD_NAME — inspect musl DESTDIR install / re-run gmake sysroot"
# Require the loader resolve to a non-empty file (symlink to libc.so is OK).
_ld_real="$(realpath -q "$SYSROOT/lib/$MUSL_LD_NAME" 2>/dev/null || true)"
[ -n "$_ld_real" ] && [ -s "$_ld_real" ] || \
	lf_die "broken musl dynamic linker at $SYSROOT/lib/$MUSL_LD_NAME"

# --- hello ---
lf_log "--- link lf-hello (Linux ELF) ---"
HELLO_C="$BUILD/hello.c"
HELLO_OUT="$SYSROOT/bin/lf-hello"
mkdir -p "$SYSROOT/bin"
printf '%s\n' \
	'#include <stdio.h>' \
	'int main(void){puts("lfs-from-freebsd: hello from FreeBSD-built Linux userspace");return 0;}' \
	>"$HELLO_C"

# clang defaults to -lgcc for non-FreeBSD targets; FreeBSD has no Linux libgcc.
# Link musl CRT + libc explicitly (same shape as a musl-gcc wrapper).
"$CLANG" --target="$CLANG_TRIPLE" \
	--sysroot="$SYSROOT" \
	-fuse-ld=lld \
	-nostdlib \
	-O2 \
	-Wl,-dynamic-linker,/lib/$MUSL_LD_NAME \
	"$SYSROOT/usr/lib/crt1.o" \
	"$SYSROOT/usr/lib/crti.o" \
	"$HELLO_C" \
	-L"$SYSROOT/usr/lib" \
	-lc \
	"$SYSROOT/usr/lib/crtn.o" \
	-o "$HELLO_OUT"

file "$HELLO_OUT" | tee "$LF_OUT/toolchain/spike-hello.file"
# Prefer llvm-readobj NEEDED/interp over file(1) grepping an injected linker path.
command -v llvm-readobj >/dev/null 2>&1 || \
	lf_die "llvm-readobj required to verify lf-hello (pkg install llvm)"
_needed="$(llvm-readobj --needed-libs "$HELLO_OUT")" || \
	lf_die "llvm-readobj --needed-libs failed for $HELLO_OUT — rebuild sysroot"
printf '%s\n' "$_needed" | grep -Eq 'libc\.so' || \
	lf_die "lf-hello missing NEEDED libc.so (got: $_needed) — clean out/sysroot and gmake sysroot"
_prog="$(llvm-readobj --program-headers "$HELLO_OUT")" || \
	lf_die "llvm-readobj --program-headers failed for $HELLO_OUT — rebuild sysroot"
printf '%s\n' "$_prog" | grep -Fq "Name: /lib/$MUSL_LD_NAME" || \
	lf_die "lf-hello INTERP must be /lib/$MUSL_LD_NAME — rebuild sysroot / check wrappers"

# Record env fragment for later chapters (replace prior spike block if present).
ENVF="$LF_OUT/toolchain/env.sh"
printf '%s' "$CLANG_TRIPLE" | grep -Eq '^[A-Za-z0-9._+-]+$' || \
	lf_die "refusing CLANG_TRIPLE=$CLANG_TRIPLE"
if [ -f "$ENVF" ]; then
	awk '!/^# Appended by spike-freebsd-linux-sysroot.sh/ && !/^export LF_SYSROOT=/ && !/^export LF_CLANG_LINUX_TRIPLE=/' \
		"$ENVF" >"$ENVF.tmp"
	[ -s "$ENVF.tmp" ] || lf_die "failed rewriting $ENVF"
	mv "$ENVF.tmp" "$ENVF"
fi
{
	echo "# Appended by spike-freebsd-linux-sysroot.sh"
	echo "export LF_SYSROOT=\"$SYSROOT\""
	echo "export LF_CLANG_LINUX_TRIPLE=\"$CLANG_TRIPLE\""
} >>"$ENVF"

lf_log "SYSROOT=$SYSROOT"
lf_log "hello=$HELLO_OUT"
lf_log "=== spike OK (FreeBSD-built Linux sysroot + hello) ==="
