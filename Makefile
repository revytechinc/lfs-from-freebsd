# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# FreeBSD make(1) wrapper — re-exec with GNU make (gmake).
# The real rules live in GNUmakefile.

.MAIN: all

.if !defined(_LF_GMAKE_WRAP)
_LF_GMAKE_WRAP= 1
.export _LF_GMAKE_WRAP

.PHONY: all help fetch toolchain kernel busybox initramfs openzfs rootfs iso \
	test-boot test-boot-bios test-install test-desktop builder chapters clean distclean

.for _t in all help fetch toolchain kernel busybox initramfs openzfs rootfs iso \
	test-boot test-boot-bios test-install test-desktop builder chapters clean distclean
${_t}:
	@command -v gmake >/dev/null 2>&1 || { echo "gmake required (pkg install gmake)" >&2; exit 1; }
	@exec gmake -C ${.CURDIR} -f GNUmakefile ${_t} ${.MAKEFLAGS}
.endfor
.endif
