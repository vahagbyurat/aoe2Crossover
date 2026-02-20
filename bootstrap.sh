#!/usr/bin/env bash
set -eo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/win-compat"
cp -r "$SRC" "$HOME/win-compat"
chmod +x "$HOME/win-compat/scripts/setup.sh"
exec "$HOME/win-compat/scripts/setup.sh"
