# Linux builder guest

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## Purpose

Some steps (OpenZFS Linux module link, glibc, multi-pass GCC, chroot) need a
**real Linux userspace**. FreeBSD remains the orchestrator and still owns:

- version pins (`versions.env`)
- Linux kernel build (pure FreeBSD HOSTCC + LLVM — no linuxulator)
- ISO packaging
- ZFS install story / bhyve tests

The builder is an **Alpine Linux VM under bhyve**, not an ABI emulator.

## Distro choice (v1)

Default: **Alpine Linux** virt ISO (musl *builder* host; LFS DESTDIR still
targets **glibc** userspace). Pinned as `BUILDER_ALPINE_*` in `versions.env`.

## Lifecycle

| Script | Role |
|--------|------|
| `create.sh` | Stage Alpine ISO + empty disk + `state.env` |
| `start.sh` | bhyve UEFI boot; virtio-9p share of `out/` + `vendor/` |
| `stop.sh` | destroy VM |
| `alpine-answers` | `setup-alpine -f` answerfile (sys install to `/dev/vda`) |
| `guest-build-openzfs.sh` | Run **in the guest** after 9p mount |

### First boot (operator)

```sh
doas ./scripts/builder-guest/create.sh   # once
doas ./scripts/builder-guest/start.sh    # serial console

# In Alpine live (root, empty password):
mkdir -p /mnt/lfs
mount -t 9p -o trans=virtio lfs /mnt/lfs
setup-alpine -f /mnt/lfs/alpine-answers
reboot
# Remove ISO from start.sh args or eject CD after install, reboot from disk
```

### OpenZFS (in guest, after disk install + 9p remount)

```sh
mount -t 9p -o trans=virtio lfs /mnt/lfs
sh /mnt/lfs/guest-build-openzfs.sh
# Results: out/zfs/destdir + out/zfs/modules on the FreeBSD host share
```

## Shared data

Default v1: **virtio-9p** share named `lfs` → guest `/mnt/lfs` with
`out/` and `vendor/` symlinks. No linuxulator; FreeBSD only serves files.

## State file

`out/builder/state.env` (not committed) — VM name, disk paths, optional
`BUILDER_SSH` once networking is added.
