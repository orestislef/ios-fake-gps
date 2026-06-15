#!/usr/bin/env bash
#
# One-time setup for the Python sidecar.
#
# The runtime is installed in ~/.ios-fake-gps (a home dot-folder) rather than the
# repo, because the privileged tunnel daemon runs as root and macOS TCC blocks
# root from reading ~/Documents, ~/Desktop and ~/Downloads.
set -euo pipefail

RUNTIME="$HOME/.ios-fake-gps"
REPO="$(cd "$(dirname "$0")" && pwd)"

echo "Creating runtime in $RUNTIME"
mkdir -p "$RUNTIME"

if [ ! -x "$RUNTIME/venv/bin/python" ]; then
  python3 -m venv "$RUNTIME/venv"
fi

"$RUNTIME/venv/bin/pip" install --upgrade pip
"$RUNTIME/venv/bin/pip" install -r "$REPO/sidecar/requirements.txt"
cp "$REPO/sidecar/gpsd_helper.py" "$RUNTIME/gpsd_helper.py"

echo
echo "Done."
echo "Next:"
echo "  1. Start the tunnel (keep it running):"
echo "       sudo $RUNTIME/venv/bin/python -m pymobiledevice3 remote tunneld"
echo "  2. Run the app:"
echo "       cd macapp && swift run"
