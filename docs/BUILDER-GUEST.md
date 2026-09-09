# Linux builder guest

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## Purpose

Some LFS steps (glibc configure, multi-pass GCC, chroot) assume a Linux
kernel ABI and Linux `/proc` semantics. Rather than pretend FreeBSD’s
Linuxulator is a full LFS host, we run those chapters inside a **bhyve Linux
guest** while FreeBSD remains the orchestrator and still owns:

- version pins (`versions.env`)
- kernel build
- ISO packaging
- ZFS install story

## Distro choice (v1)

Default: **Alpine Linux** cloud/virt image (musl host for the *builder*; the
LFS DESTDIR still builds **glibc** LFS userspace into a separate tree). Alpine
is small and boots quickly under bhyve.

Pinned version: `BUILDER_ALPINE_VERSION` in `versions.env`.

Alternative (documented only): Debian cloud image if a chapter needs glibc
on the *builder* itself — switch via `BUILDER_DISTRO` and document the change
in this file.

## Lifecycle scripts

| Script | Role |
|--------|------|
| `scripts/builder-guest/create.sh` | Download image, create raw disk, first-boot cloud-init/seed |
| `scripts/builder-guest/start.sh` | bhyve start, wait for SSH |
| `scripts/builder-guest/stop.sh` | graceful stop / destroy |
| `scripts/builder-guest/run-chapter.sh` | copy chapter + run under SSH |
| `scripts/builder-guest/run-next-chapter.sh` | pick next pending `chapters/*.sh` |
| `scripts/builder-guest/sync-destdir.sh` | pull DESTDIR into FreeBSD `out/rootfs` |

## Shared data

Prefer:

1. Virtio-9p or NFS export of `vendor/` and `out/` from FreeBSD, **or**
2. `rsync` over SSH before/after each chapter (simpler; default v1).

Chapter scripts must treat `$LFS` / `$DESTDIR` as the LFS root being built —
not the Alpine system root.

## State file

`out/builder/state.env` records:

- VM name
- SSH host/port/key
- last completed chapter id
- DESTDIR path inside the guest

Do not commit this file (lives under `out/`).
