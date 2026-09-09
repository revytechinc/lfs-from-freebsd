# GPL / CDDL redistribution notes

<!-- Copyright (c) 2026 REVYTECH, Inc. -->

This project **intentionally** builds and packages GPL-2.0 (Linux, BusyBox,
many LFS packages) and CDDL (OpenZFS) software. That is allowed; it creates
**obligations** if you redistribute binaries or ISOs.

This document is operator guidance, not legal advice. When in doubt, read the
upstream licenses in each `vendor/` tree and consult counsel.

## What this repo’s BSD-3-Clause covers

Only the glue authored in this repository: scripts, Makefile, docs, overlays
we wrote, config templates. See `LICENSE`.

## What an ISO typically contains

| Component | Typical license | Source location after fetch |
|-----------|-----------------|-----------------------------|
| Linux kernel | GPL-2.0 | `vendor/linux-*.tar.xz` |
| BusyBox | GPL-2.0 | `vendor/busybox-*.tar.bz2` |
| OpenZFS | CDDL (+ some GPL compatibility notes upstream) | `vendor/zfs-*.tar.gz` |
| Limine | mostly BSD/zlib — check tarball | `vendor/limine-*.tar.xz` |
| LFS package set | mixed (GPL, LGPL, BSD, MIT, …) | per-package under vendor / builder |

## If you publish `lfs-from-freebsd.iso` or disk images

At minimum, plan to:

1. **Ship or offer corresponding source** for GPL components at the versions
   you built (the `vendor/` tarballs plus any patches applied from this repo).
2. **Preserve copyright and license notices** inside the image where upstream
   expects them.
3. **Document how to obtain source** next to the download (README section or
   `SOURCES.txt` on the ISO).
4. Respect **CDDL** obligations for OpenZFS (source availability for CDDL
   portions you modify/distribute).

A practical pattern for this project:

- Tag a git commit for each published ISO.
- Attach or link the exact `vendor/` tarball set (or a source ISO).
- Keep `versions.env` SHA256s so recipients can verify.

## Patches

Any patch this repo applies to GPL software should be included alongside the
pristine tarball (e.g. `patches/`). Prefer quilt-style clear diffs.

## What not to do

- Do not strip license files from rootfs “to save space.”
- Do not claim the ISO is “BSD licensed” as a whole.
- Do not mix in proprietary blobs without documenting them separately.
