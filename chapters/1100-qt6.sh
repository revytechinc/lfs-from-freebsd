#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
# Scaffold only — refuses to claim completion until pins + build exist.
set -eu
: "${LFS:?}"; : "${LF_CHAPTER_ID:=1100}"
echo "=== chapter ${LF_CHAPTER_ID}: not implemented yet (see docs/DESKTOP-PLASMA6.md) ==="
echo "Refusing to write .done until versions are pinned and the package is built."
exit 1
