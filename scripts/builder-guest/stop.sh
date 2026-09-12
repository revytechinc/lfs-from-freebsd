#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# Alpine builder guest — disabled (docs/ARCHITECTURE.md).
set -eu
echo "ERROR: Alpine builder guest is disabled. Run 'gmake sysroot' then 'gmake chapter CHAPTER=chapters/<id>.sh' (see docs/ARCHITECTURE.md)" >&2
exit 1

