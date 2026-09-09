# UEFI boot (required — with BIOS)

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## Policy

**UEFI is mandatory** for v1 live media, installed disks, and primary smoke
tests. **Legacy BIOS is also mandatory** on the same hybrid image — see
[BOOT-AND-ISO.md](BOOT-AND-ISO.md) for the full BIOS + UEFI contract.

This file focuses on the **UEFI / ESP** half. Do not read it as UEFI-only;
omitting BIOS El Torito / `limine bios-install` is a bug.

| Artifact | UEFI requirement | BIOS requirement |
|----------|------------------|------------------|
| Live ISO | El Torito EFI + `EFI/BOOT/BOOTX64.EFI` (Limine) | El Torito BIOS + hybrid MBR (`limine bios-install`) |
| Installed disk | GPT + ESP (FAT32) with Limine; kernels on ESP | `limine bios-install` on the disk (+ BIOS boot partition if required) |
| bhyve tests | `make test-boot` → `BHYVE_UEFI_CODE.fd` | `make test-boot-bios` |
| VMware / other | Guest firmware = EFI **or** BIOS | Both must be documented green over time |

## ESP layout (installed and ISO EFI image)

```
ESP (FAT32)
├── EFI/
│   └── BOOT/
│       └── BOOTX64.EFI          # Limine UEFI application (removable path)
├── boot/
│   ├── limine.conf
│   ├── vmlinuz                  # FreeBSD-built Linux kernel
│   └── initramfs.img
└── limine.conf                  # optional root copy — keep in sync
```

The removable-media path `EFI/BOOT/BOOTX64.EFI` is required so firmware finds
a bootloader without NVRAM boot entries (critical for ISO and first install).

After install, Limine may also register a boot entry; still keep `BOOTX64.EFI`
so the disk remains bootable if NVRAM is cleared.

## Secure Boot

v1: Secure Boot **off**. Signing Limine/kernel is a later phase.

## Relation to ZFS root

UEFI firmware never reads the ZFS pool. It only loads Limine from the ESP.
Limine loads the kernel; the initramfs imports `rpool` and mounts
`rpool/ROOT/lfs`. Same after a BIOS boot — only the firmware→Limine path
differs.

## See also

- [BOOT-AND-ISO.md](BOOT-AND-ISO.md) — hybrid ISO, Limine, tests
- [ZFS-ROOT.md](ZFS-ROOT.md) — pool/dataset layout
- [DESKTOP-PLASMA6.md](DESKTOP-PLASMA6.md) — SDDM/Plasma after install
