# Building the Linux kernel from FreeBSD (host tools)

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## What works natively on FreeBSD

- Fetch + verify sources (`gmake fetch`)
- LLVM/clang can emit `x86_64-linux-gnu` objects (toolchain probe)
- `defconfig` / `olddefconfig` with **gmake**, **bison**, **flex**
- ISO packaging with Limine + xorriso once `bzImage` exists

## Host-tool friction

Linux kbuild still compiles **host** utilities (`scripts/`, `tools/objtool`,
`arch/x86/tools/relocs`) with `HOSTCC`. Those expect a Linux-ish environment:

| Symptom | Mitigation in this repo |
|---------|-------------------------|
| BSD `make` parses kernel Makefile | Always `gmake`; `export MAKE=gmake` |
| `bison` / `flex` missing | `pkg install bison flex` |
| `install -m` fails | `pkg install coreutils`; `INSTALL=ginstall` |
| SELinux `mdp` needs `asm/types.h` | `CONFIG_SECURITY_SELINUX=n` in fragment |
| objtool needs Linux asm headers | `CONFIG_OBJTOOL=n`, frame-pointer unwinder |
| `relocs.c` ARRAY_SIZE / clang | Prefer ports **gcc** as `HOSTCC` (`LF_HOSTCC=gcc14`) |

If FreeBSD-native kbuild still fails, use the **hybrid fallback**: build the
kernel inside the Linux builder guest (`docs/BUILDER-GUEST.md`) while FreeBSD
keeps orchestration, fetch, and ISO. That remains “from a FreeBSD environment”
in the project sense.

## Required packages (kernel)

```sh
doas pkg install -y gmake bison flex coreutils gcc14 llvm19
```

Optional: `export LF_HOSTCC=gcc14 LF_CLANG=clang19`
