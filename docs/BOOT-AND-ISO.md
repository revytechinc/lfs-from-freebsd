# Boot and ISO layout — BIOS + UEFI hybrid

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## Requirement

**Both legacy BIOS and UEFI must boot** the live ISO and the installed disk.
v1 does not ship a single-firmware image.

| Firmware | Bootloader pieces |
|----------|-------------------|
| UEFI (x86_64) | `EFI/BOOT/BOOTX64.EFI` (Limine) on ESP / EFI El Torito image |
| Legacy BIOS | Limine BIOS CD bootstrap + hybrid MBR; on disk, `limine bios-install` |

Limine is chosen because one config (`limine.conf`) drives **both** paths and
avoids GRUB-on-ZFS feature fights. Kernels and initramfs still live on VFAT
ESP for the installed system (see [ZFS-ROOT.md](ZFS-ROOT.md)).

## Why hybrid (not UEFI-only)

- Nested virt / lab hosts and older hypervisors still default to SeaBIOS.
- the CloudBSD build host bhyve tests often use UEFI; desktop VMware/VirtualBox users may
  pick either firmware.
- The project claim is a complete bootable medium — firmware lock-in is a bug.

## Live ISO structure

```
lfs-from-freebsd.iso          # hybrid: El Torito BIOS + EFI + isohybrid MBR
├── boot/
│   ├── limine-bios.sys       # Limine BIOS stage
│   ├── limine-bios-cd.bin    # El Torito BIOS boot image
│   ├── limine-uefi-cd.bin    # El Torito EFI boot image (FAT)
│   ├── limine.conf           # shared menu (BIOS + UEFI)
│   ├── vmlinuz
│   └── initramfs.img
├── EFI/BOOT/BOOTX64.EFI      # also present for USB/dd-style boots
└── live/
    └── rootfs.squashfs
```

Exact file names follow the Limine release layout used by
`scripts/build-iso.sh`. If Limine renames artifacts across versions, update
this document in the **same** commit as the script.

### xorriso contract (FreeBSD host)

`build-iso.sh` must roughly:

1. Stage tree under `out/iso/tree/`.
2. Install Limine BIOS + UEFI CD binaries into `boot/`.
3. Invoke `xorriso` with **both**:
   - BIOS El Torito (`-b boot/limine-bios-cd.bin` / Limine-documented flags)
   - EFI El Torito (`-e boot/limine-uefi-cd.bin -no-emul-boot`)
4. Run `limine bios-install` on the ISO when required by the Limine version
   (hybrid MBR), per upstream “BIOS+UEFI hybrid ISO” instructions for that
   pin in `versions.env`.

Never omit the BIOS El Torito entry to “simplify” UEFI testing.

## Installed disk

GPT layout remains:

1. ESP (FAT32) — Limine UEFI + `limine.conf` + kernels/initramfs  
2. BIOS boot partition (if required by Limine on GPT) **or** Limine’s
   documented BIOS embed path — see Limine GPT BIOS notes for the pinned
   version  
3. OpenZFS `rpool`

`install-to-zfs.sh` must:

- `limine bios-install /dev/DISK` (or equivalent for the pinned Limine)
- Copy `BOOTX64.EFI` to `EFI/BOOT/` on the ESP
- Write one `limine.conf` used by both firmware types

## limine.conf (shared)

Template: `config/limine/limine.conf.in`

- One menu entry for live (`lfs.live=1`)
- One entry pattern for installed (`root=ZFS=rpool/ROOT/lfs`)
- Serial console enabled so bhyve nmdm shows Limine + early kernel messages
  under **both** firmware modes

## Initramfs contract

`/init` (BusyBox ash script) must:

1. Mount `/proc`, `/sys`, `/dev` (and `devtmpfs` if needed).
2. Parse cmdline (`lfs.live=1`, `root=ZFS=…`, `spl.spl_hostid=…`).
3. **Live:** find and mount squashfs or drop to a BusyBox shell with installer.
4. **Installed:** `modprobe zfs` (if modular), `zpool import -N rpool`, mount
   the root dataset, `exec switch_root` (or BusyBox equivalent).

Failure modes must print a clear message and spawn a rescue shell — silent
hangs are unacceptable for a teaching/LFS project.

Firmware type (BIOS vs UEFI) must not change the initramfs contract; only the
bootloader path differs.

## bhyve / VM smoke tests

| Target | Firmware | Script |
|--------|----------|--------|
| `make test-boot` | UEFI (`BHYVE_UEFI_CODE.fd`) | `vm-boot-test.sh` |
| `make test-boot-bios` | Legacy BIOS / CSM if available | `vm-boot-test.sh --bios` |
| `make test-install` | Prefer UEFI; document BIOS install in ROADMAP | `vm-boot-test.sh --install` |

`scripts/vm-boot-test.sh` should:

1. Allocate a temporary VM name (`lfs-boot-$$`).
2. For UEFI: use `BHYVE_UEFI_CODE.fd` + writable VARS copy.
3. For BIOS: boot without UEFI firmware (bhyve default bootrom / SeaBIOS
   equivalent as available on the host) — document host-specific flags in
   [BUILD-HOST.md](BUILD-HOST.md).
4. Attach the ISO; serial console; wait for a known prompt.
5. Destroy the VM; leave logs under `out/logs/`.

For `--install`, attach a second empty disk, run the installer non-interactively,
reboot from that disk without the ISO, and confirm Limine appears under the
same firmware mode used for the test.
