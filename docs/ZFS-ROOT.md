# ZFS root — installed system contract

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## Layout

| Piece | Role |
|-------|------|
| GPT partition 1 | ESP, FAT32, ~512M–1G — Limine, kernels, initramfs |
| GPT partition 2 | OpenZFS pool `rpool` (whole remaining disk) |

### Datasets

| Dataset | Properties (intent) |
|---------|---------------------|
| `rpool` | pool root |
| `rpool/ROOT` | container; `canmount=off` |
| `rpool/ROOT/lfs` | actual `/`; `mountpoint=/`; `canmount=noauto`; set as `bootfs` |
| `rpool/home` | `/home` |

Names are pinned in `versions.env` (`ZFS_POOL`, `ZFS_ROOT_DATASET`, …).
Installer and initramfs **must** read the same names.

## Why `canmount=noauto` on the root dataset?

So a host that can see the pool does not auto-mount Linux `/` over FreeBSD’s
`/`, and so the initramfs controls when the dataset appears. This matches
common OpenZFS-on-Linux practice (Debian Root-on-ZFS docs).

## Hostid

ZFS on Linux needs a stable hostid early. Prefer writing `/etc/hostid` into
the initramfs (and installed system) via `zgenhostid` once OpenZFS userspace
exists. Until then, pass `spl.spl_hostid=0x…` on the kernel cmdline.

## Installer (`scripts/install-to-zfs.sh`)

Must be safe to run from the live environment:

1. Require an explicit disk argument (or `--auto` with a documented discovery
   rule for the test harness).
2. Refuse to operate on the live medium itself.
3. Partition, `zpool create`, create datasets, rsync/copy rootfs, install
   ESP contents, write Limine config with `root=ZFS=…`.
4. Export the pool cleanly before reboot.

## Live vs installed overlays

- `overlays/live/` — installer UI, live banners, `lfs.live` helpers.
- `overlays/installed/` — fstab-less ZFS mounts, hostid, hostname defaults,
  **and** desktop enablement (SDDM, Plasma 6 session) once Milestone C
  chapters have populated the rootfs. See [DESKTOP-PLASMA6.md](DESKTOP-PLASMA6.md).

Never copy live-only markers onto the installed root without stripping them.

The installer must:

- Merge `overlays/installed/` after the base rootfs copy.
- Ensure SDDM is the graphical login manager on the installed system only.
- Create the operator user with membership in `video`, `audio`, and `input`
  so Plasma/Wayland can access DRM and input devices.
