# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# Top-level build for lfs-from-freebsd.
# Intended host: FreeBSD CURRENT amd64 (see docs/BUILD-HOST.md).
#
# versions.env is included by Make AND sourced by shell scripts — keep it
# Make-safe: no quotes around values, no $(...), no spaces in values.

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include $(ROOT)/versions.env
export

OUT := $(abspath $(ROOT)/out)
VENDOR := $(ROOT)/vendor
VENDOR := $(abspath $(VENDOR))
SCRIPTS := $(ROOT)/scripts

.PHONY: all help fetch toolchain kernel busybox initramfs openzfs rootfs iso \
	test-boot test-boot-bios test-install test-desktop builder chapters clean distclean

all: iso

help:
	@echo "lfs-from-freebsd targets:"
	@echo "  fetch       download and verify pinned sources"
	@echo "  toolchain   build/prepare Linux-targeting tools on FreeBSD"
	@echo "  kernel      build Linux kernel on FreeBSD (LLVM)"
	@echo "  busybox     build or stage BusyBox for initramfs/rootfs"
	@echo "  initramfs   assemble live/install initramfs"
	@echo "  openzfs     build OpenZFS for the built kernel (builder guest if needed)"
	@echo "  rootfs      assemble live root filesystem tree"
	@echo "  iso         build BIOS+UEFI hybrid live ISO (Limine)"
	@echo "  test-boot   boot ISO in bhyve UEFI (smoke)"
	@echo "  test-boot-bios  boot ISO with legacy BIOS firmware (smoke)"
	@echo "  test-install  ISO -> ZFS install -> cold boot"
	@echo "  test-desktop  installed SDDM/Plasma smoke (Milestone C)"
	@echo "  builder     create/start Linux builder guest for LFS chapters"
	@echo "  chapters    run next pending LFS chapter script in builder"
	@echo "  clean       remove out/"
	@echo "  distclean   remove out/ and vendor/"

fetch:
	$(SCRIPTS)/fetch-sources.sh

toolchain:
	$(SCRIPTS)/build-cross-toolchain.sh

kernel: fetch toolchain
	$(SCRIPTS)/build-linux-kernel.sh

busybox: fetch
	$(SCRIPTS)/build-busybox-initramfs.sh busybox-only

initramfs: busybox kernel
	$(SCRIPTS)/build-busybox-initramfs.sh

openzfs: kernel
	$(SCRIPTS)/build-openzfs.sh

rootfs: initramfs
	$(SCRIPTS)/build-rootfs.sh

iso: rootfs
	$(SCRIPTS)/build-iso.sh

test-boot: iso
	$(SCRIPTS)/vm-boot-test.sh --uefi

test-boot-bios: iso
	$(SCRIPTS)/vm-boot-test.sh --bios

test-install: iso openzfs
	$(SCRIPTS)/vm-boot-test.sh --install --uefi

test-desktop: test-install
	$(SCRIPTS)/vm-boot-test.sh --desktop --uefi

builder:
	$(SCRIPTS)/builder-guest/create.sh
	$(SCRIPTS)/builder-guest/start.sh

chapters: builder
	$(SCRIPTS)/builder-guest/run-next-chapter.sh

clean:
	@test "$(OUT)" = "$(abspath $(ROOT)/out)" || (echo "OUT override refused" >&2; exit 1)
	rm -rf "$(OUT)"

distclean: clean
	@test "$(VENDOR)" = "$(abspath $(ROOT)/vendor)" || (echo "VENDOR override refused" >&2; exit 1)
	rm -rf "$(VENDOR)"
