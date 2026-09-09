#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# builder-guest/stop.sh
set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/common.sh"
lf_need_freebsd
NAME="${1:-lfs-builder}"
bhyvectl --vm="$NAME" --destroy 2>/dev/null || true
lf_log "destroyed $NAME"
