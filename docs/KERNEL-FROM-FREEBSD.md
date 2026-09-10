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
| `relocs.c` ARRAY_SIZE / clang | Prefer ports **gcc** or linuxulator gcc as `HOSTCC` |
| objtool needs Linux `asm/*.h` | Prefer **`/compat/linux/usr/bin/gcc`** (`linux-rl9-devtools`) so host tools see real Linux headers |

### Recommended FreeBSD host packages for native-ish kbuild

```sh
doas pkg install -y gmake bison flex coreutils gcc14 \
  linux_base-rl9 linux-rl9-devtools
```

Then:

```sh
export LF_HOSTCC=/compat/linux/usr/bin/gcc
export LF_HOSTCXX=/compat/linux/usr/bin/g++
export LF_HOSTLD=/compat/linux/usr/bin/ld
export LF_HOSTAR=/compat/linux/usr/bin/ar
export MAKE=gmake INSTALL=ginstall
gmake kernel
```

Do **not** put `/compat/linux/usr/bin` first on `PATH` for the outer `gmake`
invocation — Linux `uname` then shadows FreeBSD and `lf_need_freebsd` fails.
`build-linux-kernel.sh` stages a **binutils-only** directory
(`out/linux-host-bin` with `ld`/`as`/…) so collect2 links with Linux ld/libelf
while FreeBSD `uname`/`gmake`/`sh` stay first.
