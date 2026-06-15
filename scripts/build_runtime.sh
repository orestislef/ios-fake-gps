#!/usr/bin/env bash
#
# Freeze the Python sidecar + tunnel daemon into ONE standalone binary
# (dist_pyi/fakegps-runtime/) using PyInstaller, so the shipped app needs no
# Python install on the target machine.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PYTHON:-$HOME/.ios-fake-gps/venv/bin/python}"

cd "$REPO"
rm -rf build_pyi dist_pyi

"$PY" -m PyInstaller \
  --name fakegps-runtime \
  --onedir --noconfirm --clean \
  --workpath build_pyi --distpath dist_pyi --specpath build_pyi \
  --paths sidecar \
  --hidden-import gpsd_helper \
  --collect-all pymobiledevice3 \
  --collect-all developer_disk_image \
  --recursive-copy-metadata pymobiledevice3 \
  sidecar/fakegps_runtime.py

echo
echo "Built: $REPO/dist_pyi/fakegps-runtime/fakegps-runtime"
