# Troubleshooting

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## `clang --target=x86_64-linux-gnu` fails on FreeBSD

**Symptom:** unknown target or missing `linux` headers during compile.

**Mitigation:** install ports LLVM (`pkg install llvm19`) and set:

```sh
export LF_CLANG=/usr/local/bin/clang19
export LF_LLVM_PREFIX=/usr/local/llvm19
```

Base clang on CURRENT sometimes works; ports LLVM is the supported escape hatch.
Document which one worked on the CloudBSD build host in `out/logs/` and update
[BUILD-HOST.md](BUILD-HOST.md) if the default should change.

## Kernel build wants GNU `as` / binutils

Prefer `LLVM=1` / `LLVM_IAS=1` so the integrated assembler is used. If a
driver still demands GNU as, install a Linux-targeting binutils from ports
or build that piece in the builder guest.

## BusyBox cross-build fails

Phase 1 may stage the official static musl BusyBox binary (see `versions.env`).
That is a **bootstrap**, not the end state — record in ROADMAP when the
FreeBSD cross-build path works and prefer it.

## OpenZFS `./configure` will not run on FreeBSD

Expected. Build OpenZFS against the FreeBSD-built kernel tree **inside the
Linux builder guest**, with `--with-linux=` / `--with-linux-obj=` pointed at
the exported kernel build directory. See `scripts/build-openzfs.sh`.

## bhyve boots firmware then blackholes

- Confirm UEFI code/vars paths.
- Confirm the ISO has a valid EFI El Torito image (`xorriso -indev … -report_el_torito as_mkisofs`).
- Attach a serial console; Limine and early kernel messages often only appear there.
- Ensure the kernel has `CONFIG_EFI_STUB`, virtio, and serial (`CONFIG_SERIAL_8250_CONSOLE` / virtio-console as applicable).

## ZFS import fails in initramfs

- Missing modules in initramfs (`zfs`, `spl`, dependencies).
- Hostid mismatch — regenerate `/etc/hostid` and rebuild initramfs.
- Wrong dataset name vs cmdline `root=ZFS=…`.
- Pool feature incompatibility if the live OpenZFS userspace is older than
  the pool created elsewhere — keep installer and initramfs on the **same**
  OpenZFS version pin.

## Builder guest SSH never comes up

- Check `ifconfig` / tap bridge on the FreeBSD host (`examine-host-environment-first`).
- Cloud-init seed may be wrong; fall back to Alpine “virtual” image with a
  known root password **only on isolated build nets**, and rotate — do not
  commit secrets.
