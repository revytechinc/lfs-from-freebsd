# FreeBSD-hosted Linux cross userspace (spike)

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## Goal

Prove we can produce a **Linux sysroot and a linked Linux userspace binary
entirely on FreeBSD** — no Linux VM and no linuxulator. A native FreeBSD
jail is allowed later for isolation ([ARCHITECTURE.md](ARCHITECTURE.md));
this spike runs on the host.

This is the Milestone B foundation under [ARCHITECTURE.md](ARCHITECTURE.md).

## Status (amd64 FreeBSD build host)

**Spike green.** `gmake spike-sysroot` exits 0 and produces:

```
out/sysroot/bin/lf-hello: ELF 64-bit LSB pie executable, x86-64, … interpreter /lib/ld-musl-x86_64.so.1
```

FreeBSD-host notes:

- Linux `headers_install` needs `gsed` on `PATH` as `sed`, plus the same
  `relocs.h` FreeBSD ELF compat shim as `build-linux-kernel.sh`.
- musl `./configure --target=` invents `$TRIPLE-ar` — use clang `--target=` in
  `CC` only; `AR=llvm-ar`.
- FreeBSD clang has **no on-disk** `libclang_rt.builtins.a`; musl’s configure
  still records `-lgcc`. Spike builds tiny Linux-ELF `__mul{s,d,x}c3` stubs and
  sets `LIBCC=` to that archive; hello is linked with `-nostdlib` + musl CRT.
- FreeBSD `file(1)` does **not** print the word `Linux`; accept `ld-musl` in
  the interpreter path.

## Spike acceptance (thin slice)

On an amd64 FreeBSD build host:

1. `gmake toolchain` records a clang that can emit `TARGET_TRIPLE` objects.
2. `scripts/spike-freebsd-linux-sysroot.sh` (or successor):
   - installs Linux UAPI headers into `out/sysroot`
   - cross-builds **musl** into `out/sysroot` using FreeBSD clang + `ld.lld`
   - links a small `hello` ELF for Linux against that sysroot
3. `file out/sysroot/bin/lf-hello` shows ELF x86-64 with musl interpreter
   (`ld-musl-x86_64.so.1`). FreeBSD `file` may omit the word “Linux”.
4. Optional later: boot that binary under the FreeBSD-built kernel in bhyve
   (static link first to avoid dynamic loader path pain).

glibc remains a follow-on once musl (or an equivalent) sysroot path is green.

## Layout

```
out/toolchain/env.sh     # LF_CLANG, TARGET_TRIPLE, LLVM tools
out/sysroot/             # --sysroot for later chapters
  usr/include/           # Linux + libc headers
  lib/                   # libc, crt
  bin/lf-hello           # spike probe (optional install path)
```

## Non-goals for the spike

- Full LFS chapter runner on FreeBSD (comes after sysroot works)
- Qt / Plasma
- Re-using Alpine `chapters/*.sh` unchanged (they assume Linux host `apk`,
  musl builder quirks, etc. — rewrite drivers, keep pins)

## Operator

```sh
gmake fetch toolchain
gmake spike-sysroot
# or: ./scripts/spike-freebsd-linux-sysroot.sh
```

Requires: FreeBSD, `llvm`/`clang` with Linux target, `ld.lld`, `gmake`,
`gsed` (for kernel headers), pinned `musl` + `linux` tarballs in `vendor/`
(see `versions.env`).

## Next / chapter runner

```sh
gmake wrappers          # libgcc stubs + $TRIPLE-gcc → clang wrappers
gmake chapter CHAPTER=chapters/0000-host-prep.sh
gmake chapters-freebsd CHAPTERS='chapters/0000-host-prep.sh'
```

- `scripts/run-chapter-freebsd.sh` — FreeBSD path of record (no Alpine SSH).
  Default `LFS=out/lfs` (do not reuse Alpine root-owned `out/destdir`).
- Alpine `chapters/*.sh` are a **pin/order map**; many still assume `$LFS/tools`
  GNU cross — wrappers symlink that farm to FreeBSD clang. Expect per-chapter
  fixes (meson, pkgconf, host tools) as batches land.
- Do **not** resume Alpine `make builder` / `make chapters`.
