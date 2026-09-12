#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# stage-linux-libgcc-stubs.sh — put clang-friendly libgcc stubs in out/sysroot.
#
# WHAT: Linux-ELF __mul{s,d,x}c3 archive installed as libgcc.a (+ empty eh/s).
# WHY:  FreeBSD clang has no on-disk builtins; musl/configure and normal links
#       still pass -lgcc / -lgcc_s / -lgcc_eh.
# HOST: FreeBSD only.
# OUT:  out/sysroot/usr/lib/libgcc*.a and libgcc_s.so
# DOCS: docs/FREEBSD-CROSS-USERSPACE.md
set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
lf_need_freebsd
lf_mkdirs

# shellcheck disable=SC1091
. "$LF_ROOT/versions.env"
[ -f "$LF_OUT/toolchain/env.sh" ] || lf_die "missing out/toolchain/env.sh (gmake toolchain)"
# shellcheck disable=SC1091
. "$LF_OUT/toolchain/env.sh"

SYSROOT="${LF_SYSROOT:-$LF_OUT/sysroot}"
case "$SYSROOT" in
*".."*) lf_die "SYSROOT must not contain .." ;;
"$LF_OUT"/*) ;;
*) lf_die "SYSROOT must be under $LF_OUT (got $SYSROOT)" ;;
esac
[ -d "$SYSROOT" ] || lf_die "missing $SYSROOT (gmake spike-sysroot first)"
lf_path_under "$SYSROOT" "$LF_OUT"
[ -d "$SYSROOT/usr/include" ] || lf_die "missing $SYSROOT (gmake spike-sysroot first)"

CLANG="$(lf_clang)"
CLANG_TRIPLE="${LF_CLANG_LINUX_TRIPLE:-x86_64-unknown-linux-musl}"
AR="${LF_LLVM_AR:-$(command -v llvm-ar)}"
BUILD="$LF_OUT/build/libgcc-stubs"
mkdir -p "$BUILD" "$SYSROOT/usr/lib"

lf_ranlib() {
	_a="$1"
	if command -v llvm-ranlib >/dev/null 2>&1; then
		"${LF_LLVM_RANLIB:-$(command -v llvm-ranlib)}" "$_a"
	else
		"$AR" s "$_a"
	fi
}

STUB_C="$BUILD/compiler-rt-complex-stubs.c"
cat >"$STUB_C" <<'EOF'
/* Minimal compiler-rt helpers for musl + clang on FreeBSD (Linux ELF). */
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

"$CLANG" --target="$CLANG_TRIPLE" -ffreestanding -fPIC -O2 -c "$STUB_C" -o "$BUILD/stubs.o"
"$AR" rc "$SYSROOT/usr/lib/libgcc.a" "$BUILD/stubs.o"
lf_ranlib "$SYSROOT/usr/lib/libgcc.a"
# Empty unwind companion — satisfies -lgcc_eh without pulling FreeBSD objects.
"$AR" rc "$SYSROOT/usr/lib/libgcc_eh.a"
lf_ranlib "$SYSROOT/usr/lib/libgcc_eh.a"
# Shared libgcc_s: linker script so -lgcc_s resolves without a real DSO yet.
printf 'GROUP ( libgcc.a )\n' >"$SYSROOT/usr/lib/libgcc_s.so"

lf_log "staged libgcc stubs under $SYSROOT/usr/lib"
