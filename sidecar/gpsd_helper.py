#!/usr/bin/env python3
"""
ios-fake-gps sidecar.

A long-lived helper that holds ONE developer connection to a tethered iPhone
open and streams simulated GPS coordinates to it. The macOS app (SwiftUI) speaks
to this process over stdin/stdout using newline-delimited JSON ("NDJSON").

Why a persistent process instead of calling `pymobiledevice3 ... set` per point:
iOS 17+ requires a RemoteXPC developer tunnel, and each fresh CLI invocation
re-does an expensive handshake. For smooth movement we push a new coordinate
~once per second, so we open the LocationSimulation DVT channel once and reuse it.

Prerequisite: the tunneld daemon must be running (needs root):

    sudo pymobiledevice3 remote tunneld

It manages the per-device tunnels and auto-mounts the Developer Disk Image.
This sidecar then borrows an RSD (RemoteServiceDiscovery) connection from it.

Protocol
--------
Commands in  (one JSON object per line on stdin):
    {"cmd": "set",   "lat": 40.69, "lon": -74.04, "id": 12}
    {"cmd": "clear",                               "id": 13}
    {"cmd": "ping",                                "id": 14}
    {"cmd": "devices"}
    {"cmd": "quit"}

Events out (one JSON object per line on stdout):
    {"event": "ready",   "device": {...}}
    {"event": "ok",      "id": 12}
    {"event": "pong",    "id": 14}
    {"event": "devices", "devices": [...]}
    {"event": "error",   "message": "...", "fatal": true|false, "id": 12}
    {"event": "bye"}

stderr carries human-readable logs only; stdout is strictly NDJSON.
"""
import argparse
import asyncio
import json
import sys
from contextlib import AsyncExitStack
from typing import Any, Optional

from pymobiledevice3.exceptions import TunneldConnectionError
from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation
from pymobiledevice3.tunneld.api import (
    TUNNELD_DEFAULT_ADDRESS,
    get_tunneld_device_by_udid,
    get_tunneld_devices,
)


def emit(obj: dict[str, Any]) -> None:
    """Write a single NDJSON event to stdout and flush immediately."""
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def log(*args: Any) -> None:
    print("[sidecar]", *args, file=sys.stderr, flush=True)


def describe(rsd: RemoteServiceDiscoveryService) -> dict[str, Any]:
    return {
        "udid": rsd.udid,
        "name": getattr(rsd, "name", None),
        "product_type": getattr(rsd, "product_type", None),
        "product_version": getattr(rsd, "product_version", None),
    }


async def list_devices(address: tuple[str, int]) -> list[RemoteServiceDiscoveryService]:
    return await get_tunneld_devices(address)


async def pick_device(
    address: tuple[str, int], udid: Optional[str]
) -> RemoteServiceDiscoveryService:
    if udid:
        rsd = await get_tunneld_device_by_udid(udid, address)
        if rsd is None:
            raise RuntimeError(f"device {udid} not found in tunneld")
        return rsd
    rsds = await get_tunneld_devices(address)
    if not rsds:
        raise RuntimeError("no devices available from tunneld")
    # Close the ones we won't use; keep the first.
    for extra in rsds[1:]:
        try:
            await extra.close()
        except Exception:
            pass
    return rsds[0]


async def stdin_lines() -> "asyncio.StreamReader":
    """Wrap stdin as an asyncio StreamReader (works on macOS pipes)."""
    loop = asyncio.get_event_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)
    return reader


async def run(address: tuple[str, int], udid: Optional[str]) -> int:
    # --- establish the persistent connection -------------------------------
    try:
        rsd = await pick_device(address, udid)
    except TunneldConnectionError:
        emit(
            {
                "event": "error",
                "fatal": True,
                "code": "no_tunneld",
                "message": (
                    "Cannot reach tunneld at "
                    f"{address[0]}:{address[1]}. Start it with: "
                    "sudo pymobiledevice3 remote tunneld"
                ),
            }
        )
        return 2
    except Exception as e:  # noqa: BLE001
        emit({"event": "error", "fatal": True, "code": "no_device", "message": str(e)})
        return 2

    async with AsyncExitStack() as stack:
        try:
            dvt = await stack.enter_async_context(DvtProvider(rsd))
            loc = await stack.enter_async_context(LocationSimulation(dvt))
        except Exception as e:  # noqa: BLE001
            emit(
                {
                    "event": "error",
                    "fatal": True,
                    "code": "dvt_failed",
                    "message": (
                        f"Could not open LocationSimulation: {e}. "
                        "Is Developer Mode enabled and the DDI mounted?"
                    ),
                }
            )
            return 3
        stack.push_async_callback(rsd.close)

        emit({"event": "ready", "device": describe(rsd)})
        log("ready, simulating location for", rsd.udid)

        # --- command loop --------------------------------------------------
        reader = await stdin_lines()
        while True:
            raw = await reader.readline()
            if not raw:  # EOF — parent closed the pipe
                break
            line = raw.decode("utf-8", "replace").strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                emit({"event": "error", "fatal": False, "message": f"bad json: {line!r}"})
                continue

            cmd = msg.get("cmd")
            mid = msg.get("id")
            try:
                if cmd == "set":
                    await loc.set(float(msg["lat"]), float(msg["lon"]))
                    emit({"event": "ok", "id": mid})
                elif cmd == "clear":
                    await loc.clear()
                    emit({"event": "ok", "id": mid})
                elif cmd == "ping":
                    emit({"event": "pong", "id": mid})
                elif cmd == "devices":
                    devs = await list_devices(address)
                    emit({"event": "devices", "devices": [describe(d) for d in devs]})
                    for d in devs:
                        if d.udid != rsd.udid:
                            await d.close()
                elif cmd == "quit":
                    break
                else:
                    emit(
                        {
                            "event": "error",
                            "fatal": False,
                            "id": mid,
                            "message": f"unknown cmd: {cmd!r}",
                        }
                    )
            except Exception as e:  # noqa: BLE001
                emit({"event": "error", "fatal": False, "id": mid, "message": str(e)})

        # Best-effort: stop simulating before we drop the connection.
        try:
            await loc.clear()
        except Exception:
            pass

    emit({"event": "bye"})
    return 0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="ios-fake-gps sidecar")
    p.add_argument("--udid", default=None, help="target device UDID (default: first)")
    p.add_argument(
        "--tunneld-host", default=TUNNELD_DEFAULT_ADDRESS[0], help="tunneld host"
    )
    p.add_argument(
        "--tunneld-port", type=int, default=TUNNELD_DEFAULT_ADDRESS[1], help="tunneld port"
    )
    p.add_argument(
        "--list", action="store_true", help="list devices as one NDJSON event and exit"
    )
    return p.parse_args()


async def amain() -> int:
    ns = parse_args()
    address = (ns.tunneld_host, ns.tunneld_port)
    if ns.list:
        try:
            devs = await list_devices(address)
        except TunneldConnectionError:
            emit(
                {
                    "event": "error",
                    "fatal": True,
                    "code": "no_tunneld",
                    "message": "tunneld not running (sudo pymobiledevice3 remote tunneld)",
                }
            )
            return 2
        emit({"event": "devices", "devices": [describe(d) for d in devs]})
        for d in devs:
            await d.close()
        return 0
    return await run(address, ns.udid)


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(amain()))
    except KeyboardInterrupt:
        sys.exit(130)
