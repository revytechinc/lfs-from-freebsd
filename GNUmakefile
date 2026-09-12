# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# GNU Makefile for lfs-from-freebsd (use `gmake` or FreeBSD `make` wrapper).
# Intended host: FreeBSD CURRENT amd64 (see docs/BUILD-HOST.md).
#
# versions.env is included by Make AND sourced by shell scripts — keep it
# Make-safe: no quotes around values, no $(...), no spaces in values.

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include $(ROOT)/versions.env
export

OUT := $(abspath $(ROOT)/out)
VENDOR := $(abspath $(ROOT)/vendor)
SCRIPTS := $(ROOT)/scripts
LF_ARCH ?= amd64
ifneq ($(LF_ARCH),amd64)
$(error LF_ARCH=$(LF_ARCH) is not supported yet (amd64 only))
endif

.PHONY: all help fetch toolchain kernel busybox initramfs openzfs rootfs iso \
	test-boot test-boot-bios test-install test-desktop builder chapters \
	spike-sysroot sysroot chapter chapters-freebsd wrappers clean distclean

all: iso

help:
	@echo "lfs-from-freebsd targets (gmake / FreeBSD make wrapper):"
	@echo "Variables:"
	@echo "  LF_ARCH=$(LF_ARCH)  (amd64 default; aarch64 currently unsupported)"
	@echo "Targets:"
	@echo "  fetch       download and verify pinned sources"
	@echo "  toolchain   prepare FreeBSD clang/lld for Linux targets"
	@echo "  sysroot     build FreeBSD-hosted musl Linux sysroot and test binary"
	@echo "  wrappers    stage libgcc stubs + <target-triple>-gcc clang wrappers"
	@echo "  chapter     run one FreeBSD-hosted chapter (CHAPTER=chapters/0000-…)"
	@echo "  chapters-freebsd  run CHAPTERS= list (default: chapters/0000-host-prep.sh chapters/0500-zlib-libpng.sh)"
	@echo "  kernel      build Linux kernel on FreeBSD (LLVM)"
	@echo "  busybox     build or stage BusyBox for initramfs/rootfs"
	@echo "  initramfs   assemble live/install initramfs"
	@echo "  openzfs     build OpenZFS for the built Linux kernel (FreeBSD-hosted; incomplete)"
	@echo "  rootfs      assemble live root filesystem tree"
	@echo "  iso         build live amd64 ISO image"
	@echo "  test-boot   boot ISO in bhyve UEFI (smoke test)"
	@echo "  test-boot-bios  boot ISO with legacy BIOS firmware (amd64 only)"
	@echo "  test-install  ISO -> ZFS install -> cold boot"
	@echo "  test-desktop  installed SDDM/Plasma smoke (bhyve UEFI)"
	@echo "  clean       remove out/"
	@echo "  distclean   remove out/ and vendor/"
	@echo "Docs: docs/ARCHITECTURE.md (FreeBSD-only build)"
	@echo "Disabled: builder / chapters (Alpine — see ARCHITECTURE.md)"

fetch:
	$(SCRIPTS)/fetch-sources.sh

toolchain:
	$(SCRIPTS)/build-cross-toolchain.sh

sysroot spike-sysroot: fetch toolchain
	$(SCRIPTS)/spike-freebsd-linux-sysroot.sh

wrappers:
	@test -s "$(OUT)/sysroot/usr/lib/libc.a" -o -s "$(OUT)/sysroot/usr/lib/libc.so" || $(MAKE) sysroot
	$(SCRIPTS)/stage-linux-libgcc-stubs.sh
	$(SCRIPTS)/install-cross-wrappers.sh

# FreeBSD-hosted chapter runner (path of record). Override CHAPTER=…
# wrappers already implies sysroot; avoid re-entering sysroot on every chapter.
CHAPTER ?= chapters/0000-host-prep.sh
CHAPTERS ?= chapters/0000-host-prep.sh chapters/0500-zlib-libpng.sh

# Reject metacharacters before any recipe shell sees CHAPTER/CHAPTERS.
ifneq ($(CHAPTER),$(subst ',,$(CHAPTER)))
$(error CHAPTER must not contain single quotes)
endif
ifneq ($(CHAPTER),$(subst ",,$(CHAPTER)))
$(error CHAPTER must not contain double quotes)
endif
ifneq ($(CHAPTER),$(subst $$,,$(CHAPTER)))
$(error CHAPTER must not contain $$)
endif
ifneq ($(CHAPTER),$(subst `,,$(CHAPTER)))
$(error CHAPTER must not contain backticks)
endif
ifneq ($(CHAPTERS),$(subst ',,$(CHAPTERS)))
$(error CHAPTERS must not contain single quotes)
endif
ifneq ($(CHAPTERS),$(subst ",,$(CHAPTERS)))
$(error CHAPTERS must not contain double quotes)
endif
ifneq ($(CHAPTERS),$(subst ;,,$(CHAPTERS)))
$(error CHAPTERS must not contain semicolons)
endif
ifneq ($(CHAPTERS),$(subst $$,,$(CHAPTERS)))
$(error CHAPTERS must not contain $$)
endif
ifneq ($(CHAPTERS),$(subst `,,$(CHAPTERS)))
$(error CHAPTERS must not contain backticks)
endif
ifneq ($(CHAPTERS),$(subst |,,$(CHAPTERS)))
$(error CHAPTERS must not contain pipes)
endif
ifneq ($(CHAPTERS),$(subst &,,$(CHAPTERS)))
$(error CHAPTERS must not contain ampersands)
endif

chapter:
	@printf '%s' '$(CHAPTER)' | grep -Eq '^chapters/[0-9A-Za-z._-]+\.sh$$' || \
		(printf '%s\n' "ERROR: CHAPTER must match chapters/<id>.sh" >&2; exit 1)
	@test -s "$(OUT)/sysroot/usr/lib/libc.a" -o -s "$(OUT)/sysroot/usr/lib/libc.so" || $(MAKE) wrappers
	@test -x "$(OUT)/toolchain/bin/$(TARGET_TRIPLE)-gcc" || $(MAKE) wrappers
	$(SCRIPTS)/run-chapter-freebsd.sh '$(CHAPTER)'

chapters-freebsd:
	@test -n "$(strip $(CHAPTERS))" || \
		(echo 'ERROR: CHAPTERS is empty; set CHAPTERS="chapters/0000-host-prep.sh chapters/0500-zlib-libpng.sh"' >&2; exit 1)
	@test -s "$(OUT)/sysroot/usr/lib/libc.a" -o -s "$(OUT)/sysroot/usr/lib/libc.so" || $(MAKE) wrappers
	@test -x "$(OUT)/toolchain/bin/$(TARGET_TRIPLE)-gcc" || $(MAKE) wrappers
	@$(foreach c,$(CHAPTERS),printf '%s' '$(c)' | grep -Eq '^chapters/[0-9A-Za-z._-]+\.sh$$' || exit 1; $(SCRIPTS)/run-chapter-freebsd.sh '$(c)' &&) true

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
	@echo "ERROR: make builder is disabled (Alpine guest builder is deprecated)." >&2
	@echo "Build on FreeBSD only — see docs/ARCHITECTURE.md and gmake sysroot." >&2
	@exit 1

chapters:
	@echo "ERROR: 'make chapters' has been replaced." >&2
	@echo "Use: gmake chapter CHAPTER=chapters/0000-host-prep.sh" >&2
	@echo "  or: gmake chapters-freebsd" >&2
	@echo "See docs/ARCHITECTURE.md / docs/FREEBSD-CROSS-USERSPACE.md" >&2
	@exit 1

clean:
	@test "$(OUT)" = "$(abspath $(ROOT)/out)" || (echo "OUT override refused" >&2; exit 1)
	rm -rf "$(OUT)"

distclean: clean
	@test "$(VENDOR)" = "$(abspath $(ROOT)/vendor)" || (echo "VENDOR override refused" >&2; exit 1)
	rm -rf "$(VENDOR)"
