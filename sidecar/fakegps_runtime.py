#!/usr/bin/env python3
"""
Combined runtime entry point, frozen by PyInstaller into a single standalone
binary that ships inside FakeGPS.app — so end users need no Python install.

Usage:
    fakegps-runtime tunneld [args...]   # runs `pymobiledevice3 remote tunneld`
    fakegps-runtime sidecar [args...]   # runs the location-simulation sidecar
"""
import sys


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    rest = sys.argv[2:]

    if mode == "tunneld":
        from pymobiledevice3.__main__ import main as pmd3_main
        sys.argv = ["pymobiledevice3", "remote", "tunneld"] + rest
        pmd3_main()
        return 0

    if mode == "sidecar":
        import asyncio
        import gpsd_helper
        sys.argv = ["gpsd_helper"] + rest
        return asyncio.run(gpsd_helper.amain())

    sys.stderr.write("usage: fakegps-runtime {tunneld|sidecar} [args...]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
