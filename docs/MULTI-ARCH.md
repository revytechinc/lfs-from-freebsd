# Multi-arch — amd64 first, then aarch64

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## Order (non-negotiable)

1. **amd64 (x86_64)** — primary. Milestone A → B → C must pass on amd64
   under **bhyve** and **VMware** (Workstation/Fusion Intel or nested).
2. **aarch64 (arm64)** — **only after** amd64 desktop acceptance
   (SDDM + logged-in Plasma 6). Targets Apple Silicon Macs (VMware Fusion
   arm64 / UTM) and FreeBSD/CloudBSD aarch64 hosts.

Do not block amd64 work on aarch64. Do not ship an aarch64 ISO as “ready”
until the amd64 path is green.

## Why aarch64

Operators with Apple Macs (M1/M2/M3/…) need a guest that runs under
VMware Fusion or similar on arm64. Same product story: FreeBSD builds
Linux, hybrid UEFI (no legacy BIOS on aarch64), OpenZFS root, Plasma 6 +
SDDM, **open-vm-tools** on VMware.

## Build host matrix

| Guest arch | Preferred FreeBSD build host | Notes |
|------------|------------------------------|--------|
| amd64 | FreeBSD CURRENT amd64 | Pure FreeBSD `HOSTCC` + LLVM `ARCH=x86_64` |
| aarch64 | FreeBSD aarch64 host **or** amd64→aarch64 LLVM cross | Prefer native aarch64; cross only if documented |

Userspace chapters for either arch are **FreeBSD-hosted cross** into a
Linux sysroot ([ARCHITECTURE.md](ARCHITECTURE.md)) — no Linux VM/jail and
no linuxulator as a build helper.

## Artifact layout

```
out/
  amd64/   # or keep today’s flat out/ as amd64 alias until cutover
  aarch64/
```

v1 may keep `out/` meaning amd64 and add `out/aarch64/` when Milestone C
amd64 is done. ISO names:

- `out/lfs-from-freebsd-amd64.iso` (alias of today’s ISO)
- `out/lfs-from-freebsd-aarch64.iso`

## Kernel / boot differences (aarch64)

| Piece | amd64 | aarch64 |
|-------|-------|---------|
| Linux `ARCH=` | `x86_64` | `arm64` |
| Image | `bzImage` | `Image.gz` (or `Image`) |
| Firmware | BIOS + UEFI | **UEFI only** |
| Limine | bios + uefi-x86-64 | uefi-aarch64 |
| VMware GPU | `vmwgfx` | Fusion arm64 path (virtio-gpu and/or vendor) |
| open-vm-tools | required | required on Fusion |

Config fragment: `config/kernel/lfs-from-freebsd.config` (amd64) plus
`config/kernel/lfs-from-freebsd-aarch64.config` (delta / full fragment).

## Make interface (planned)

```sh
gmake iso                    # amd64 (default LF_ARCH=amd64)
gmake iso LF_ARCH=aarch64    # only after amd64 Milestone C
gmake test-desktop LF_ARCH=amd64
gmake test-desktop LF_ARCH=aarch64
```

`LF_ARCH` defaults to `amd64`. Scripts that assume `bzImage` must branch
on arch.

## Exit criteria (aarch64)

Same as amd64 Milestone C, on an Apple Silicon (or aarch64) VMware/UTM VM:

1. UEFI boot of hybrid-capable medium (UEFI-only is fine).
2. Install to ZFS → cold boot `rpool/ROOT/lfs`.
3. **SDDM** greeter → log in → **Plasma 6**.
4. `vmtoolsd` running under VMware Fusion.

## Status

- [x] Documented sequencing (this file)
- [ ] `LF_ARCH` plumbing in `scripts/common.sh` / `GNUmakefile`
- [ ] aarch64 kernel fragment + Limine UEFI-AA64 ISO path
- [ ] FreeBSD-hosted aarch64-linux sysroot spike (same shape as amd64 musl)
- [ ] First aarch64 ISO after amd64 Milestone C green
