# lfs-from-freebsd

**On FreeBSD: build a Linux kernel, live ISO, and LFS-based system with an OpenZFS root.**

Usual story is “build FreeBSD while running Linux.” This repo is the other
direction: **a FreeBSD host builds Linux** (kernel + live media), then walks
[Linux From Scratch](https://www.linuxfromscratch.org/) into an **OpenZFS**
installed root (`rpool/ROOT/lfs`).

GPL / CDDL upstream sources are first-class here (see [NOTICE](NOTICE) and
[docs/GPL-REDISTRIBUTION.md](docs/GPL-REDISTRIBUTION.md)). Project glue
(scripts, Makefile, docs) is BSD-3-Clause ([LICENSE](LICENSE)).

## Claim (what we are proving)

| Layer | Who builds it | Notes |
|-------|---------------|--------|
| Linux kernel | **FreeBSD host** (LLVM / `clang --target=x86_64-linux-gnu`) | Phase 1 |
| Live initramfs + BusyBox | FreeBSD host (cross or staged static bootstrap) | Phase 1 |
| Live ISO + **BIOS + UEFI** hybrid (Limine) | FreeBSD host (`xorriso` + `limine bios-install`) | Phase 1 |
| OpenZFS modules/utils for that kernel | FreeBSD when possible; else Linux builder guest | Phase 2 |
| ZFS disk install + cold boot | Live ISO installer | Phase 2 |
| Classic LFS package chapters (glibc, …) | **Linux builder guest** under bhyve, driven by FreeBSD scripts | Phase 3 |
| **KDE Plasma 6 + SDDM** (installed root only) | Linux builder guest (BLFS-style); live ISO stays minimal | Phase C |

This is the **hybrid** model from the project plan: FreeBSD owns orchestration,
kernel, packaging, and ISO; a disposable Linux guest runs chapters that fight
cross-compilation. The **installed** ZFS system is intended to boot to
**SDDM** and a **KDE Plasma 6** session (see [docs/DESKTOP-PLASMA6.md](docs/DESKTOP-PLASMA6.md)).

## Quick start (build host: FreeBSD)

Recommended host: FreeBSD CURRENT **amd64** (operator notes in
[docs/BUILD-HOST.md](docs/BUILD-HOST.md)).

```sh
git clone git@github.com:revytechinc/lfs-from-freebsd.git
cd lfs-from-freebsd

# Host packages (once)
doas pkg install -y xorriso mtools squashfs-tools e2fsprogs gmake bash curl git bison flex

gmake fetch          # or: make fetch  (BSD make wrapper → gmake)
gmake toolchain
gmake kernel
gmake initramfs
gmake iso            # out/lfs-from-freebsd.iso (BIOS + UEFI hybrid)
gmake test-boot      # bhyve UEFI smoke boot to a shell
gmake test-boot-bios # bhyve/legacy BIOS smoke boot (when firmware available)
```

Installed systems also get **both** firmware paths (ESP + Limine BIOS install).
Desktop (**SDDM + KDE Plasma 6**) is merged only onto the **installed** ZFS
root — see [docs/DESKTOP-PLASMA6.md](docs/DESKTOP-PLASMA6.md) and
[docs/BOOT-AND-ISO.md](docs/BOOT-AND-ISO.md).

Full ZFS install proof:

```sh
make openzfs
make test-install   # ISO → install to virt disk → cold boot from ZFS
```

LFS chapter walker (after milestone A works):

```sh
make builder        # create/start Alpine (or similar) builder VM
make chapters       # run next pending chapters/*.sh inside the guest
```

## Documentation map

Read these before changing behaviour:

| Document | Purpose |
|----------|---------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Hybrid build, boot path, ZFS layout, data flow |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phase A → B checklist and LFS chapter map |
| [docs/BUILD-HOST.md](docs/BUILD-HOST.md) | the CloudBSD build host setup, packages, disk/ZFS notes |
| [docs/BOOT-AND-ISO.md](docs/BOOT-AND-ISO.md) | Limine hybrid **BIOS + UEFI**, ESP, initramfs, live vs installed |
| [docs/UEFI-BOOT.md](docs/UEFI-BOOT.md) | ESP / `BOOTX64.EFI` details (BIOS still required — see BOOT-AND-ISO) |
| [docs/ZFS-ROOT.md](docs/ZFS-ROOT.md) | Pool/dataset design, installer contract |
| [docs/BUILDER-GUEST.md](docs/BUILDER-GUEST.md) | Linux guest used for LFS chapters |
| [docs/GPL-REDISTRIBUTION.md](docs/GPL-REDISTRIBUTION.md) | What you owe if you ship an ISO |
| [docs/DESKTOP-PLASMA6.md](docs/DESKTOP-PLASMA6.md) | Installed-only KDE Plasma 6 + SDDM (BLFS track) |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common FreeBSD→Linux build failures |
| [versions.env](versions.env) | Pinned versions + SHA256 (source of truth) |

Every script under `scripts/` starts with a comment block describing **what**,
**why**, **host assumptions**, and **outputs**. Prefer extending those comments
when you change behaviour.

## Repository layout

```
lfs-from-freebsd/
  Makefile                 # top-level targets (see `make help`)
  versions.env             # pinned URLs + checksums
  LICENSE NOTICE LICENSES/ # project vs third-party licenses
  docs/                    # design and operator docs (start here)
  scripts/                 # FreeBSD-hosted build/orchestration
  scripts/builder-guest/   # Linux VM lifecycle for LFS chapters
  config/kernel/           # Linux .config for virt + ZFS-capable boots
  config/limine/           # Limine config templates
  overlays/live/           # files merged into live rootfs
  overlays/installed/      # files merged only onto installed ZFS root
  chapters/                # one script per LFS chapter (runs in builder)
  vendor/                  # fetched sources (gitignored)
  out/                     # build products (gitignored)
```

## Status

See [docs/ROADMAP.md](docs/ROADMAP.md) for the live checklist.

- Milestone **A** — ISO boots Linux and installs to ZFS (shell).
- Milestone **B** — installed ZFS root grows into LFS userspace.
- Milestone **C** — **installed** system runs **SDDM + KDE Plasma 6**
  (live ISO stays minimal; see [docs/DESKTOP-PLASMA6.md](docs/DESKTOP-PLASMA6.md)).

## License summary

- **This repo’s glue:** BSD-3-Clause (`LICENSE`).
- **Linux kernel, BusyBox, many LFS packages:** GPL-2.0 (and related).
- **OpenZFS:** primarily CDDL.
- Shipping binaries/ISOs requires complying with those upstream licenses —
  not only this repo’s BSD header.
