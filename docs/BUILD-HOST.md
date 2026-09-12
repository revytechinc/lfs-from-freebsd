# Build host — FreeBSD / CloudBSD CURRENT

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## Canonical host

| Field | Value |
|-------|--------|
| OS | FreeBSD / CloudBSD CURRENT (amd64) |
| Role | Fetch, FreeBSD-hosted cross builds, ISO, bhyve/VMware tests (Linux = DUT) |
| Home clone | `~/git/lfs-from-freebsd` |
| Disk | Large `zroot` — keep `vendor/` and `out/` on a dataset with room |

Fleet hostnames stay in private runbooks. This file is the operator map for
whatever FreeBSD CURRENT machine you use (see your org inventory).

Always inventory before changing host networking or creating VMs — see the
shared skill `examine-host-environment-first` if you touch bridges/jails.

## Required packages

Install once (names are FreeBSD ports/pkg):

```sh
doas pkg install -y \
  xorriso mtools squashfs-tools e2fsprogs \
  gmake bash curl git wget gsed nasm gcc14 \
  cdrtools bison flex coreutils seabios
```

**Pure FreeBSD** — do not install `linux_base-*` / linuxulator toolchains for
this repo. Kernel host tools use FreeBSD `gcc14` or base `clang`. Optional:
a **native FreeBSD jail** (no linuxulator) to isolate risky chapter builds —
see [ARCHITECTURE.md](ARCHITECTURE.md).

Kernel kbuild needs **bison**, **flex**, **GNU install** (`ginstall` from
`coreutils`), and **GNU sed** (`gsed`) — FreeBSD `sed` cannot run the
`voffset.h` recipe (`\|` BRE). Use **`gmake`** (or plain `make`, which wraps
to gmake via the BSD Makefile). GNU Make functions (`abspath`, `lastword`) are
required; FreeBSD `make` alone cannot parse `GNUmakefile`.

Notes:

- **Clang/LLVM:** FreeBSD base `clang` on CURRENT often already registers
  `x86_64` and can compile with `--target=x86_64-linux-gnu`. If kernel build
  fails on missing Linux target bits, install `llvm19` (or newer) from pkg and
  point `LF_CLANG` / `LF_LLVM_PREFIX` at it (see `scripts/build-cross-toolchain.sh`).
- **bhyve UEFI:** `/usr/local/share/uefi-firmware/BHYVE_UEFI_CODE.fd` (and
  VARS) must exist for `make test-boot`.
- **BIOS tests:** `make test-boot-bios` needs SeaBIOS
  (`pkg install seabios` → `/usr/local/share/seabios/bios.bin`), or set
  `LF_BIOS_ROM`.
- **Limine ISO:** `pkg install nasm` (BIOS stage assemble).
- **doas/root:** ISO assembly and bhyve usually need elevated privileges for
  `mdconfig`, raw disks, or `bhyve` itself.

## Environment variables

| Variable | Meaning | Default |
|----------|---------|---------|
| `LF_ROOT` | Repo root | detected from script location |
| `LF_CLANG` | Clang used for Linux target | `clang` or ports llvm |
| `LF_JOBS` | Parallelism | `sysctl -n hw.ncpu` |
| `LF_BUILDER_SSH` | SSH target for builder guest | set by builder scripts |

Source of version pins: always `versions.env` from the repo root.

## Working practices

1. Build as the normal user where possible; escalate only where the script says.
2. Log long steps to `out/logs/<target>-<timestamp>.log`.
3. Do not commit `vendor/` or `out/`.
4. After a green gate, update checkboxes in [ROADMAP.md](ROADMAP.md).

## Cloning / updating

```sh
mkdir -p ~/git && cd ~/git
git clone git@github.com:revytechinc/lfs-from-freebsd.git
cd ~/git/lfs-from-freebsd && git pull --ff-only
```

## Disk / ZFS tips on the host

- Prefer a dedicated dataset for build artifacts if `/home` quotas bite.
- Snapshot `out/rootfs` between LFS chapter batches so a bad chapter does not
  force a full rebuild.
