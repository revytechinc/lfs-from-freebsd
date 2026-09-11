# Architecture — lfs-from-freebsd

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

This document is the design contract. Scripts implement it; if a script
disagrees with this file, **fix the script or update this file in the same
change** — do not leave them divergent.

## Why hybrid?

Classic [Linux From Scratch](https://www.linuxfromscratch.org/) assumes you
are already on a Linux host with a working toolchain. Our product claim is
the reverse of the nested-virt work: **drive Linux construction from FreeBSD**.

**Pure FreeBSD on the build host** — no linuxulator, no `/compat/linux` host
tools. FreeBSD clang/LLVM cross-builds the Linux kernel; FreeBSD packages
assemble the hybrid ISO and run bhyve tests.

A pure FreeBSD→Linux build of *everything* (especially glibc and the LFS
temporary toolchain, and OpenZFS’s Linux module link) still needs a **real
Linux builder VM** for those chapters — not an ABI emulator:

```
┌─────────────────────────────────────────────────────────────────┐
│                     FreeBSD build host                          │
│  (the CloudBSD build host / CloudBSD)                            │
│                                                                 │
│  • fetch + verify sources                                       │
│  • cross-build Linux kernel (LLVM, FreeBSD HOSTCC)              │
│  • assemble BusyBox initramfs / live root                       │
│  • build Limine hybrid UEFI ISO                                 │
│  • orchestrate bhyve smoke tests                                │
│  • create/start Linux builder guest                             │
│  • publish out/*.iso artifacts                                  │
└────────────────────────────┬────────────────────────────────────┘
                             │ ssh / virtio / shared out+vendor
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              Linux builder guest (bhyve)                        │
│                                                                 │
│  • LFS chapter scripts (glibc, binutils, gcc passes, …)         │
│  • OpenZFS configure/build when Linux-only                      │
│  • writes into DESTDIR → synced back to FreeBSD out/rootfs      │
└─────────────────────────────────────────────────────────────────┘
```

## Boot modes (required)

The live ISO **and** the installed disk image must boot on both:

| Mode | Mechanism (v1) |
|------|----------------|
| **UEFI** | Limine `BOOTX64.EFI` on ESP / El Torito EFI image |
| **Legacy BIOS** | Limine BIOS/CD bootstrap (hybrid MBR + El Torito BIOS) |

Do not ship a UEFI-only or BIOS-only medium for v1. `scripts/build-iso.sh`
must produce a **hybrid** ISO; `scripts/install-to-zfs.sh` must install
Limine for **both** firmware types onto the target disk (ESP + BIOS boot
gap / `limine bios-install` as documented by Limine).

Smoke tests:

- `make test-boot` — UEFI bhyve (primary on the CloudBSD build host).
- `make test-boot-bios` — BIOS/SeaBIOS path when firmware is available.
- Installed-disk tests cover both once install wiring lands.

See [BOOT-AND-ISO.md](BOOT-AND-ISO.md).

### Live ISO (BIOS or UEFI → same Limine menu)

1. Firmware loads Limine (BIOS CD/MBR **or** UEFI `BOOTX64.EFI`).
2. Limine loads `vmlinuz` + `initramfs.img` with cmdline suitable for live:
   `lfs.live=1` (and later ZFS-related params only for installed boots).
3. Initramfs `/init`:
   - mounts `proc`, `sys`, `dev`
   - loads OpenZFS modules if present (live may use squashfs/tmpfs without
     importing a pool)
   - mounts the live squashfs (or falls back to a BusyBox-only root)
   - `switch_root` / exec into live userspace → shell or installer menu

### Installed ZFS root (BIOS + UEFI)

1. Limine on disk: ESP (UEFI) **and** BIOS install (`limine bios-install`).
2. Cmdline includes `root=ZFS=rpool/ROOT/lfs` (and hostid if required).
3. Initramfs imports `rpool`, mounts the bootfs dataset on a staging dir,
   then `switch_root` into it.

We deliberately **do not** rely on GRUB reading ZFS for v1. Kernels and
initramfs live on the ESP; OpenZFS only needs to work **after** the kernel
is running. See [ZFS-ROOT.md](ZFS-ROOT.md).

## Artifact flow

```
versions.env ──► vendor/ (tarballs)
                      │
                      ▼
              out/linux/  (bzImage, modules, headers)
                      │
         ┌────────────┼────────────┐
         ▼            ▼            ▼
   out/initramfs  out/rootfs   out/zfs/ (modules+utils)
         │            │            │
         └────────────┼────────────┘
                      ▼
              out/lfs-from-freebsd.iso
                      │
                      ▼
              bhyve install → rpool/ROOT/lfs
                      │
                      ▼
         (after Milestone C chapters)
         SDDM greeter → KDE Plasma 6 session
```

Desktop stack details: [DESKTOP-PLASMA6.md](DESKTOP-PLASMA6.md).

## Version pinning

All upstream versions and SHA256 digests live in [`versions.env`](../versions.env).
`scripts/fetch-sources.sh` refuses to proceed on checksum mismatch. Empty
SHA256 for an optional bootstrap URL means “download and record” — prefer
filling it before CI.

## Licensing boundary

- **Glue** (this repo’s authored files): BSD-3-Clause.
- **Payload** inside the ISO: GPL-2.0 kernel/BusyBox, CDDL OpenZFS, etc.

Operators who redistribute ISOs must read [GPL-REDISTRIBUTION.md](GPL-REDISTRIBUTION.md).

## Non-goals (v1)

- Multi-arch (arm64, etc.)
- GRUB-on-ZFS / bootfs on ZFS with full feature set
- Replacing the LFS book — we **automate** it, we do not redefine package sets
- Shipping a general-purpose Linux distro with a package manager
- Plasma on the **live** ISO (desktop is **installed-only**; Milestone C)
