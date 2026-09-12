# Architecture — lfs-from-freebsd

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

This document is the design contract. Scripts implement it; if a script
disagrees with this file, **fix the script or update this file in the same
change** — do not leave them divergent.

## Product claim (normative)

**FreeBSD is the only build host.** FreeBSD compiles the Linux payload and
packages hybrid ISOs / disk images. Those images **install and run a Linux
OS** (bhyve, VMware, …).

Hard refusals for the *build* path:

- No **Linux VM** as a compile helper (including Alpine `lfs-builder`)
- No **Linux jail** / Linux ABI jail as a compile helper
- No **linuxulator** / `/compat/linux` as `HOSTCC` / `HOSTLD` / toolchain
- No nested Linux VM **inside** a FreeBSD jail used for builds

**Allowed isolation:** a **native FreeBSD jail** (same FreeBSD userland, no
linuxulator) may wrap risky build steps — DESTDIR experiments, unpack/build
of untrusted tarballs, chapter batches that might trash the host tree. The
jail still cross-compiles Linux with FreeBSD clang/`ld.lld` + `out/sysroot`;
it is not a Linux guest.

Linux under bhyve or VMware is allowed only as a **test target** (boot the
artifact), never as a builder.

Historical Alpine builder notes: [BUILDER-GUEST.md](BUILDER-GUEST.md)
(**non-normative**). Do not extend that path.

## Why this shape?

Classic [Linux From Scratch](https://www.linuxfromscratch.org/) assumes you
already run Linux. This project is the other direction: **FreeBSD builds
Linux** end-to-end for packaging, instead of “orchestrate a Linux guest to
do the real work.”

```
┌─────────────────────────────────────────────────────────────────┐
│                     FreeBSD build host                          │
│  (CloudBSD fleet / developer FreeBSD)                            │
│                                                                 │
│  • fetch + verify sources (versions.env)                        │
│  • FreeBSD-hosted *-linux-gnu cross toolchain + sysroot         │
│  • cross-build Linux userspace into DESTDIR / out/rootfs        │
│  • cross-build Linux kernel (LLVM, FreeBSD HOSTCC)              │
│  • OpenZFS Linux modules against FreeBSD-built kernel tree      │
│  • assemble BusyBox initramfs / live root / Limine hybrid ISO   │
│  • publish out/*.iso                                            │
│  • orchestrate bhyve / VMware smoke tests (Linux = DUT only)    │
└─────────────────────────────────────────────────────────────────┘
```

### Cross toolchain + sysroot (userspace)

Userspace is **cross-compiled on FreeBSD** into a Linux DESTDIR:

1. Build or refresh `out/toolchain/` (clang/`ld.lld` targeting
   `TARGET_TRIPLE`, plus any binutils the spike requires).
2. Populate `out/sysroot/` (Linux headers + libc — musl and/or glibc as the
   milestone requires) **on FreeBSD**, as files — not by booting Linux.
3. Chapter scripts run **on FreeBSD** with
   `CC=$TRIPLE-clang` / `--sysroot=$LF_OUT/sysroot` (exact driver TBD by
   the FreeBSD-cross spike) and install into `out/destdir` / `out/rootfs`.

Empty SHA256 in `versions.env` still means **do not fetch/build** that
package.

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
         out/toolchain + out/sysroot   (FreeBSD-built)
                      │
         ┌────────────┼────────────┐
         ▼            ▼            ▼
   out/linux/   out/destdir/   out/zfs/
   (bzImage)    (cross pkgs)   (modules)
         │            │            │
         └────────────┼────────────┘
                      ▼
              out/lfs-from-freebsd.iso
                      │
                      ▼
         bhyve / VMware  (test only) → rpool/ROOT/lfs
                      │
                      ▼
         (Milestone C) SDDM → Plasma 6 on installed image
```

Desktop stack details: [DESKTOP-PLASMA6.md](DESKTOP-PLASMA6.md).
Cross-userspace spike notes: [FREEBSD-CROSS-USERSPACE.md](FREEBSD-CROSS-USERSPACE.md).

## Version pinning

All upstream versions and SHA256 digests live in [`versions.env`](../versions.env).
`scripts/fetch-sources.sh` refuses to proceed on checksum mismatch. Empty
SHA256 for an optional package means **do not fetch or build** until pinned.

## Licensing boundary

- **Glue** (this repo’s authored files): BSD-3-Clause.
- **Payload** inside the ISO: GPL-2.0 kernel/BusyBox, CDDL OpenZFS, etc.

Operators who redistribute ISOs must read [GPL-REDISTRIBUTION.md](GPL-REDISTRIBUTION.md).

## Non-goals (v1 amd64)

- GRUB-on-ZFS / bootfs on ZFS with full feature set
- Replacing the LFS book — we **automate** package sets, we do not redefine them lightly
- Shipping a general-purpose Linux distro with a package manager
- Plasma on the **live** ISO (desktop is **installed-only**; Milestone C)
- Using a Linux VM or linuxulator to “make LFS easier”
- Using a FreeBSD jail *as cover* for linuxulator or a nested Linux VM

## Multi-arch (after amd64)

**amd64 first.** aarch64 (Apple Silicon / FreeBSD arm64 hosts) is Milestone D —
see [MULTI-ARCH.md](MULTI-ARCH.md). Do not start aarch64 ISO work until
amd64 reaches the desktop acceptance gate on bhyve **and** VMware.
