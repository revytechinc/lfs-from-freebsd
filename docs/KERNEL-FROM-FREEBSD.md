# Building a Linux kernel on FreeBSD — PURE FreeBSD

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## Policy

**No linuxulator.** The FreeBSD host builds the Linux kernel. Host tools and
orchestration are FreeBSD natives; FreeBSD’s LLVM emits the Linux target
(`LLVM=1`).

`LF_HOSTCC` / `LF_HOSTLD` pointing at `/compat/linux/…` is a hard error.

## What FreeBSD does natively

| Step | Tooling |
|------|---------|
| Fetch / verify | FreeBSD `fetch`/`curl`, sha256 |
| `defconfig` / fragment | `gmake`, `bison`, `flex`, FreeBSD `HOSTCC` |
| Target compile / link | FreeBSD `clang` / `ld.lld` via `LLVM=1` |
| Host utilities (`fixdep`, `relocs`, …) | FreeBSD `HOSTCC` (ports `gcc14` or base `clang`) + small stubs |
| ISO | Limine + `xorriso` on FreeBSD |

## Packages (FreeBSD only)

```sh
doas pkg install -y gmake bison flex coreutils gsed gcc14 \
  xorriso mtools squashfs-tools nasm
# optional for BIOS smoke tests:
doas pkg install -y seabios
```

Do **not** install `linux_base-*` / `linux-*-devtools` for this project.

## Build

```sh
export MAKE=gmake INSTALL=ginstall
# optional: LF_HOSTCC=gcc14   (default: first ports gcc*, else clang)
gmake kernel
```

## Host-tool mitigations (still FreeBSD)

| Friction | Mitigation |
|----------|------------|
| BSD `make` | Always `gmake` |
| FreeBSD `install` | `INSTALL=ginstall` |
| FreeBSD `sed` / `\|` in VOFFSET | `gsed` on PATH as `sed` |
| `objtool` / ORC | Disabled in fragment; empty `cmd_objtool`; drop `prepare: tools/objtool` |
| `extract-cert` / OpenSSL mix | Cert hostprog stubbed; MODULE_SIG off |
| SELinux `mdp` | `CONFIG_SECURITY_SELINUX=n` |
| Missing `<asm/types.h>` for tools/ | Tiny stub under `tools/include/asm/` |
| New clang `-Werror=*` vs Linux 6.12 | `KCFLAGS=-Wno-error=…` |

## What stays in the Linux builder guest

Not because FreeBSD is insufficient for *orchestration*, but because these
steps assume a Linux userspace ABI:

- OpenZFS `configure` + `.ko` / libzfs against the FreeBSD-built kernel tree
- Classic LFS chapters (glibc, toolchain passes, chroot)

That guest is a **real Linux VM** (Alpine under bhyve), not linuxulator.
See [BUILDER-GUEST.md](BUILDER-GUEST.md) and [ARCHITECTURE.md](ARCHITECTURE.md).
