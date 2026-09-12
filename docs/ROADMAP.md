# Roadmap — milestone A then B

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

Track progress by editing the checkboxes in this file when a gate actually
passes on the build host (prefer **the CloudBSD build host**). Do not check a
box because the script exists; check it because the exit criterion ran green.

## Milestone A — bootable Linux + ZFS install

Exit criteria:

1. `make iso` produces `out/lfs-from-freebsd.iso` on FreeBSD.
2. `make test-boot` reaches an interactive shell inside bhyve UEFI.
3. `make test-install` installs to a second virt disk and cold-boots from
   `rpool/ROOT/lfs`.

### Phase 0 — repo scaffold

- [x] Public GitHub repo `revytechinc/lfs-from-freebsd`
- [x] README, LICENSE, NOTICE, LICENSES/, versions.env, Makefile
- [x] docs/ set (architecture, build host, boot, ZFS, builder, GPL, troubleshooting)
- [x] scripts/ stubs with header documentation
- [x] Initial commit pushed; clone on the CloudBSD build host

### Phase 1 — FreeBSD-native kernel + live ISO

- [x] `make fetch` verifies all pinned tarballs
- [x] `make kernel` builds `out/linux/bzImage` via LLVM on FreeBSD (pure FreeBSD HOSTCC; no linuxulator)
- [x] BusyBox available in initramfs (cross-build or documented static bootstrap)
- [x] `make initramfs` produces `out/initramfs.img`
- [x] `make iso` produces hybrid **BIOS + UEFI** ISO with Limine
- [x] `make test-boot` → Limine menu under bhyve UEFI (live rescue shell after boot)
- [ ] `make test-boot-bios` → shell (legacy BIOS; El Torito + bios-install present, SeaBIOS serial TBD)

### Phase 2 — OpenZFS root install

- [ ] OpenZFS modules/utils for the built kernel (`out/zfs/`)
- [ ] Live installer `scripts/install-to-zfs.sh` (also on ISO)
- [ ] ESP + Limine entries with `root=ZFS=rpool/ROOT/lfs`
- [ ] Cold boot from installed disk succeeds

## Milestone B — walk LFS into the ZFS root

Exit criteria: installed system runs LFS-built core userspace (glibc, bash,
coreutils, …) with the FreeBSD-built kernel and OpenZFS root.

### Phase 3 — FreeBSD-hosted cross userspace + chapters

- [x] FreeBSD `out/toolchain` + `out/sysroot` spike green
  ([FREEBSD-CROSS-USERSPACE.md](FREEBSD-CROSS-USERSPACE.md))
- [x] Chapter runner on FreeBSD (`gmake chapter` / `run-chapter-freebsd.sh`) —
  `0000-host-prep` + `0500-zlib-libpng` green into `out/lfs` (musl ELF);
  further chapters TBD
- [ ] DESTDIR snapshots on FreeBSD ZFS between chapter batches
- [ ] Re-`make iso` / install test after userspace-changing batches
- [ ] Alpine `make builder` / `make chapters` treated as **non-normative** only
  ([BUILDER-GUEST.md](BUILDER-GUEST.md))

### LFS 12.3 chapter map (automation)

Chapter scripts live in `chapters/`. Name format: `NNNN-short-name.sh`.
Status: **pending** until the script exists *and* has been run green once.

| ID | Script (planned) | Book area | Status |
|----|------------------|-----------|--------|
| 0000 | `0000-host-prep.sh` | Host requirements / env | pending |
| 0005 | `0005-binutils-pass1.sh` | Temporary toolchain | pending |
| 0010 | `0010-gcc-pass1.sh` | Temporary toolchain | pending |
| 0015 | `0015-linux-headers.sh` | Temporary toolchain | pending |
| 0020 | `0020-glibc.sh` | Temporary toolchain | pending |
| 0025 | `0025-libstdc++-pass1.sh` | Temporary toolchain | pending |
| 0030 | `0030-binutils-pass2.sh` | Temporary toolchain | pending |
| 0035 | `0035-gcc-pass2.sh` | Temporary toolchain | pending |
| 0100 | `0100-enter-chroot.sh` | Chroot transition | pending |
| 0200 | `0200-lfs-base-packages.sh` | Base packages (batch) | pending |
| 0300 | `0300-bootscripts-or-systemd.sh` | Bootscripts / policy | pending |
| 0400 | `0400-sync-destdir.sh` | Sync DESTDIR → FreeBSD out/ | pending |

Exact package lists follow LFS 12.3; batch scripts may group chapters for
wall-clock sanity so long as [ARCHITECTURE.md](ARCHITECTURE.md) remains true
(FreeBSD still owns kernel + ISO).

### Phase 4 — harden

- [ ] `checksums.lock` or fully filled `versions.env` SHAs for every fetch
- [ ] Clear live vs installed overlays
- [ ] GPL redistribution doc reviewed
- [ ] Optional CI that only gates `fetch` + script syntax until boot tests exist

## Milestone C — KDE Plasma 6 + SDDM (installed only)

Exit criteria: after ZFS install and cold boot, **SDDM** presents a greeter;
login starts **KDE Plasma 6** (Wayland preferred). The live ISO does **not**
require Plasma.

Full design: [DESKTOP-PLASMA6.md](DESKTOP-PLASMA6.md).

- [ ] Kernel config DESKTOP options (DRM, virtio-gpu, input, framebuffer)
- [ ] `versions.env` pins for Qt6 / KF6 / Plasma6 / SDDM (+ SHA256)
- [ ] Chapters `1000`–`1600` (prereqs → Qt6 → KF6 → Plasma → SDDM → overlay → smoke)
- [ ] `overlays/installed` SDDM + Plasma session defaults
- [ ] Installer creates desktop user groups (`video`, `audio`, `input`)
- [ ] `make test-desktop` (or `vm-boot-test.sh --desktop`) proves greeter + session on bhyve
- [ ] GPL/LGPL notes for Qt/Plasma in NOTICE / GPL-REDISTRIBUTION

| ID | Script | Status |
|----|--------|--------|
| 1000 | `1000-desktop-prereqs.sh` | pending |
| 1100 | `1100-qt6.sh` | pending |
| 1200 | `1200-kde-frameworks6.sh` | pending |
| 1300 | `1300-plasma6.sh` | pending |
| 1400 | `1400-sddm.sh` | pending |
| 1450 | `1450-open-vm-tools.sh` | pending (VMware) |
| 1500 | `1500-desktop-overlay.sh` | pending |
| 1600 | `1600-desktop-smoke.sh` | pending |

Acceptance hypervisors for Milestone C: **bhyve** and **VMware** (see
[DESKTOP-PLASMA6.md](DESKTOP-PLASMA6.md)).

## Milestone D — aarch64 (after amd64 Milestone C)

**Do not start until amd64 SDDM + Plasma 6 is proven on bhyve and VMware.**

Design: [MULTI-ARCH.md](MULTI-ARCH.md). Audience: Apple Silicon Macs
(VMware Fusion arm64 / UTM) and FreeBSD aarch64 build hosts.

- [ ] `LF_ARCH=aarch64` plumbing (`common.sh`, ISO naming, `Image.gz`)
- [ ] `config/kernel/lfs-from-freebsd-aarch64.config`
- [ ] Limine UEFI-AA64 hybrid-capable ISO (UEFI-only OK)
- [ ] FreeBSD-hosted aarch64 sysroot + OpenZFS aarch64 modules
- [ ] open-vm-tools on Fusion arm64
- [ ] `make test-desktop LF_ARCH=aarch64` → SDDM + Plasma 6 login

## Definition of done (any phase)

For this project, “done” means:

1. Documented in `docs/` and script headers.
2. Runnable from FreeBSD via `make …`.
3. Proven on **the CloudBSD build host** (or documented alternate host) with a command
   transcript or log path under `out/logs/`.
