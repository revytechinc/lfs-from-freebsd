# Desktop (installed system) — KDE Plasma 6 + SDDM

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

## Scope

When the system is **installed** to ZFS (`rpool/ROOT/lfs`), it should present a
complete desktop environment:

| Component | Role |
|-----------|------|
| **SDDM** | Graphical login manager (starts on tty1 / seat0) |
| **KDE Plasma 6** | Desktop shell (plasmashell, KWin/Wayland preferred) |
| **Qt 6** | Toolkit stack required by Plasma 6 |
| **PipeWire / WirePlumber** | Session audio (BLFS-aligned) |
| **Mesa + virtio-gpu / DRM** | GPU path for VMs and bare metal |

The **live ISO** stays minimal (shell + installer) so milestone A remains
bootable without waiting on the full desktop dependency tree. Desktop packages
are merged into the **installed** root via `overlays/installed/` and
`chapters/1xxx-*.sh` (Beyond LFS / BLFS territory).

## Why this is not classic LFS

[Linux From Scratch](https://www.linuxfromscratch.org/lfs/) stops at a
command-line base system. Graphical desktops are documented in
[Beyond Linux From Scratch (BLFS)](https://www.linuxfromscratch.org/blfs/).
This project follows that split:

1. **Milestone A** — FreeBSD-built kernel + ZFS install + shell.
2. **Milestone B** — LFS userspace on that ZFS root.
3. **Milestone C (desktop)** — BLFS-style stack ending in Plasma 6 + SDDM
   on the **installed** image only.

## Build strategy (hybrid, same as LFS chapters)

Plasma 6’s dependency graph (Qt6, KDE Frameworks 6, Plasma Workspace, SDDM,
Wayland, etc.) is built inside the **Linux builder guest**, installing into
the same `DESTDIR` / LFS root that becomes `out/rootfs` for install.

FreeBSD still owns:

- kernel + OpenZFS modules
- ISO packaging
- `install-to-zfs.sh` (copies rootfs that *includes* desktop once Phase C
  chapters have completed)

## Session defaults (installed)

- Display server: **Wayland** first (`plasmawayland` / `startplasma-wayland`);
  X11 session optional as fallback if a GPU path is broken in the VM.
- SDDM theme: Breeze (Plasma default).
- Autologin: **off** by default; test harness may enable a throwaway user
  via installer flag `--autologin-demo` (never commit passwords).
- Default user: created by installer (`lfs` or operator-supplied) in the
  `video`, `audio`, `input` groups.

Files live under `overlays/installed/`:

```
overlays/installed/etc/sddm.conf.d/10-lfs.conf
overlays/installed/usr/lib/systemd/system/graphical.target.wants/sddm.service
  (or OpenRC equivalent if we stay sysv/openrc — see ROADMAP)
overlays/installed/etc/xdg/plasma-workspace/...
```

Exact init system (systemd vs sysvinit) is decided by the LFS bootscripts
chapter; SDDM unit/service files must match. Document the choice in
[ROADMAP.md](ROADMAP.md) when `0300-bootscripts-or-systemd.sh` lands.

## VM / virtio notes

On bhyve and VMware, prefer:

- `virtio-gpu` or VMware SVGA with 3D if available
- Enough RAM (≥ 4 GiB guest) for Plasma 6
- EFI boot (already required)

Kernel config must enable DRM, virtio-gpu, input (evdev), and framebuffer
helpers used by Wayland compositors — see `config/kernel/lfs-from-freebsd.config`
sections tagged `DESKTOP`.

## Chapter map (desktop)

| ID | Script | Purpose |
|----|--------|---------|
| 1000 | `1000-desktop-prereqs.sh` | Wayland, Mesa, libinput, PipeWire, … |
| 1100 | `1100-qt6.sh` | Qt 6 base |
| 1200 | `1200-kde-frameworks6.sh` | KF6 |
| 1300 | `1300-plasma6.sh` | Plasma Workspace 6 + KWin |
| 1400 | `1400-sddm.sh` | SDDM + Breeze integration |
| 1500 | `1500-desktop-overlay.sh` | Merge `overlays/installed` desktop bits |
| 1600 | `1600-desktop-smoke.sh` | Builder-side smoke (sddm-greeter --test, etc.) |

Versions for Qt/Plasma/SDDM are pinned in `versions.env` under the `DESKTOP_*`
and `PLASMA_*` / `QT6_*` / `SDDM_*` variables when those chapters are fleshed
out. Until pins exist, chapter scripts must refuse to run rather than
float to “latest”.

## Verification (installed image)

1. Install from ISO to ZFS.
2. Cold boot → SDDM greeter on the virtio/GPU console.
3. Log in → Plasma 6 shell (panel + wallpaper).
4. Log evidence under `out/logs/desktop-smoke-*.log`.

## Non-goals (v1 desktop)

- Full KDE Gear application set (Okular, Dolphin only as needed for smoke)
- Proprietary GPU drivers
- Flatpak/Snap as the primary app delivery
- Live-ISO Plasma session (optional later; not required for “when installed”)
