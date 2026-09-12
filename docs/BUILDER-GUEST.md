# Linux builder guest — NON-NORMATIVE (historical)

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

> **Status:** Guide / experiment only. **Not** part of the product build
> contract. See [ARCHITECTURE.md](ARCHITECTURE.md).
>
> Do **not** run new Milestone B/C chapters through Alpine. Do **not** treat
> a green `lfs-builder` chapter as proof of the FreeBSD-builds-Linux claim.
> Retain this tree only as reference for dependency order and pins.

## What this was

An Alpine Linux bhyve VM used to cross-build glibc LFS/BLFS packages into a
DESTDIR shared over virtio-9p. It avoided FreeBSD-hosted Linux sysroot work
by compiling on a real Linux ABI.

That contradicts the product rule: **compile on FreeBSD; Linux only as the
payload and as a test guest.**

## Superseded by

| Concern | Normative path |
|---------|----------------|
| Toolchain + libc/sysroot | FreeBSD-hosted cross → `out/toolchain`, `out/sysroot` ([FREEBSD-CROSS-USERSPACE.md](FREEBSD-CROSS-USERSPACE.md)) |
| LFS/BLFS chapters | Run on FreeBSD against that sysroot |
| Kernel | Unchanged — FreeBSD LLVM ([KERNEL-FROM-FREEBSD.md](KERNEL-FROM-FREEBSD.md)) |
| ISO / bhyve tests | Unchanged — FreeBSD packs; Linux boots the ISO |

## Scripts (frozen)

`scripts/builder-guest/*` are fail-closed stubs (`exit 1`). `make builder` /
`make chapters` refuse the same way. Historical Alpine lifecycle stays in this
doc only; do not grow those scripts.

## Lifecycle (historical reference)

| Script | Former role |
|--------|-------------|
| `create.sh` / `start.sh` / `stop.sh` | Alpine disk VM under bhyve |
| `run-chapter.sh` | scp + ssh chapter into guest |
| `guest-build-openzfs.sh` | OpenZFS inside Alpine |

Shared data was virtio-9p tag `lfs` → `/mnt/lfs`. State: `out/builder/state.env`
(not committed).
