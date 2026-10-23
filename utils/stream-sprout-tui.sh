#!/usr/bin/env bash
#
# restream — set up and run stream-sprout without hand-editing YAML.
# See utils/stream-sprout-tui.py for the actual Textual app.
#
#   gisnix restream
#   gisnix restream --config /path/to/stream-sprout.yaml
set -uo pipefail

GISNIX_ROOT="${GISNIX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export GISNIX_ROOT

exec python3 "$GISNIX_ROOT/utils/stream-sprout-tui.py" "$@"
