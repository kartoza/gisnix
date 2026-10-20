#!/usr/bin/env bash
#
# obs-setup — build gisnix's branded OBS scene collection (Kartoza or QGIS)
# by driving a locally-running OBS over obs-websocket. See utils/obs-setup.py
# for the actual scene/source definitions.
#
#   gisnix obs-setup kartoza
#   gisnix obs-setup qgis
#   gisnix obs-setup kartoza --force   # tear down and rebuild if it exists
set -uo pipefail

GISNIX_ROOT="${GISNIX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export GISNIX_ROOT

exec python3 "$GISNIX_ROOT/utils/obs-setup.py" "$@"
