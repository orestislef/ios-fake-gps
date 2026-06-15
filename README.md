<p align="center">
  <img src="assets/icon_1024.png" alt="iOS Fake GPS icon" width="160" height="160">
</p>

<h1 align="center">iOS Fake GPS</h1>

<p align="center">A Lockito-style location simulator for iPhone</p>

Simulate a static location **or** a moving route (with adjustable speed, looping
and GPS jitter) on a **non-jailbroken** iPhone, driven from a native macOS app.

This is the iOS counterpart to Android's **Lockito**. Unlike Android, iOS has no
public "mock location" API, so an app installed *on the phone* can't fake GPS for
other apps. Instead the spoof is driven from a tethered Mac over Apple's
**developer tunnel** — the same mechanism Xcode uses to simulate location while
debugging. The coordinate you set is seen **system-wide** by every app on the
device.

![The macOS app: route mode over the Bay Area, tunnel connected](docs/app.png)

> **Use responsibly.** This is meant for testing location-aware apps you own and
> for personal use. Using it to defeat anti-cheat, commit fraud, or bypass
> location-based access controls breaks those services' terms — and possibly the
> law.

## Download

Grab the latest prebuilt app from the
[**Releases**](https://github.com/orestislef/ios-fake-gps/releases) page. The
`.app` already has the Python engine bundled inside it, so you don't need to
install Python or anything else.

1. Download `FakeGPS-macos-arm64.zip` and unzip it.
2. Drag **FakeGPS.app** into your **Applications** folder.
3. The first time you open it, macOS will warn that it's from an unidentified
   developer (the app isn't notarized). **Right-click the app → Open**, then
   confirm. You only have to do this once. If it still refuses, run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/FakeGPS.app
   ```
4. Open the app, click **Start tunnel (admin)…** (it asks for your password
   once), plug in your iPhone, and hit **Connect**.

That's it — no Terminal needed for normal use. The sections below cover building
it yourself from source and the manual command-line route.

> Apple **requires** two things that no app can remove: the tunnel runs as root
> (so it asks for your password once per session), and Developer Mode has to be
> on for the iPhone. That's why a tool like this can't live on the App Store.

## Features

- **Teleport mode** — click anywhere (or search an address) to jump the device
  there instantly.
- **Route mode** — drop a series of waypoints and play them back as continuous
  movement.
- **Speed control** — 1–300 km/h; the app interpolates position every second so
  motion is smooth and realistic.
- **Loop** a route indefinitely.
- **GPS jitter** — add a few metres of random noise so the track doesn't look
  unnaturally perfect.
- **Address / place search** powered by MapKit.
- **Live position marker** showing exactly where the device currently reports it
  is, plus distance and ETA readouts.
- **One-click reset** back to the device's real GPS.
- **Auto-reset on exit** — disconnecting or quitting the app restores the phone's
  real location automatically, so you never get left on a fake position.

## How it works

```
macOS app (SwiftUI + MapKit)            Python sidecar              iPhone
  drop pins / search / route ─stdin──▶  pymobiledevice3  ──tunnel──▶  every app
  speed · loop · jitter      ◀stdout──  LocationSimulation   (DDI)     sees fake GPS
  interpolates the movement             holds 1 connection
```

- **`macapp/`** — the GUI (SwiftUI + MapKit). It owns the map, route editing and
  movement interpolation, so speed / pause / loop / jitter are all controlled on
  the Mac side rather than relying on the device's own GPX timing. It talks to
  the sidecar with newline-delimited JSON over stdin/stdout.
- **`sidecar/gpsd_helper.py`** — a small Python process that holds **one**
  developer connection open and applies each coordinate through
  `pymobiledevice3`'s `LocationSimulation` DVT channel. Keeping a single
  persistent connection avoids re-doing the slow tunnel handshake on every point
  (important when pushing a new coordinate roughly once a second).
- **`tunneld`** — `pymobiledevice3 remote tunneld`, a root daemon that creates
  the per-device RemoteXPC tunnel and auto-mounts the Developer Disk Image.
  Required on iOS 17+.

The tunnel daemon running and serving the app's requests:

![tunneld serving developer-tunnel requests](docs/tunnel.png)

## Requirements

- macOS with **Xcode** / the Swift toolchain (`swift` + `xcodebuild`).
- **Python 3.10+**.
- An iPhone on **iOS 17 or newer** with a USB cable.

## One-time setup

### 1. Python sidecar — install OUTSIDE `~/Documents`

The privileged `tunneld` daemon runs as **root**, and macOS **TCC** blocks root
from reading `~/Documents`, `~/Desktop` and `~/Downloads`. So the Python runtime
has to live somewhere root can read. Use a dot-folder in your home directory:

```bash
mkdir -p ~/.ios-fake-gps
python3 -m venv ~/.ios-fake-gps/venv
~/.ios-fake-gps/venv/bin/pip install -r sidecar/requirements.txt
cp sidecar/gpsd_helper.py ~/.ios-fake-gps/gpsd_helper.py
```

> Putting the venv under `~/Documents` makes `tunneld` die instantly with
> `PermissionError: ... pyvenv.cfg`. That's the TCC restriction at work, not a
> bug — keep the runtime in `~/.ios-fake-gps`.

### 2. iPhone

1. Connect it to the Mac by USB and tap **Trust**.
2. Enable **Settings → Privacy & Security → Developer Mode**, then reboot.

## Running it — step by step

Everything runs on the **Mac**; nothing is installed on the iPhone. Two
processes need to be alive at the same time: the **tunnel daemon** (runs as root)
and the **macOS app**. Use two Terminal windows.

### Step 1 — Plug the iPhone into the Mac with a USB cable

The connection is over **USB**. Plug the phone in and tap **Trust** on it if
prompted. (Wi-Fi works too, but only after this first USB pairing.) Make sure
**Developer Mode** is on — see the setup section above.

Check the Mac sees it:

```bash
~/.ios-fake-gps/venv/bin/pymobiledevice3 usbmux list
```

You should see your device in the output (not an empty `[]`).

### Step 2 — Terminal window 1: start the tunnel daemon (leave it running)

This needs `sudo` because it opens a network tunnel to the device. Keep this
window open the whole time:

```bash
sudo ~/.ios-fake-gps/venv/bin/python -m pymobiledevice3 remote tunneld
```

It will print log lines and keep running. The first time it also mounts the
Developer Disk Image automatically (give it a few seconds).

> Prefer not to use the Terminal? You can skip this step and click
> **Start tunnel (admin)…** inside the app instead — it shows the macOS password
> dialog and starts the same daemon for you.

### Step 3 — Terminal window 2: build and run the app

```bash
cd macapp
swift run            # builds the app and launches it
```

`swift run` compiles the Swift package and opens the window. (You can also run
`swift build` first if you just want to compile, or open `macapp/Package.swift`
in **Xcode** and press the Run button.)

### Step 4 — Connect and spoof, in the app window

1. Wait for **Tunnel daemon running** ✓ in the sidebar.
2. Click **Connect** — it shows the connected device's name and iOS version.
3. **Teleport** mode: click the map (or pick a search result) to jump the device
   there instantly.
4. **Route** mode: click to drop waypoints, set the **Speed**, optionally enable
   **Loop** and **Jitter**, then press **Play**. The green marker is the live
   simulated position; the device follows it in real time.
5. **Reset device location** clears the spoof and returns the device to real GPS.

To confirm it works, open **Apple Maps** on the iPhone and tap the location
arrow — it should show wherever you set it on the Mac.

## Quick CLI sanity check (no GUI)

With the tunnel running, this teleports the device to Liberty Island:

```bash
~/.ios-fake-gps/venv/bin/pymobiledevice3 developer dvt simulate-location set -- 40.690008 -74.045843
~/.ios-fake-gps/venv/bin/pymobiledevice3 developer dvt simulate-location clear
```

If that works, the GUI will too. Open Apple Maps on the phone and tap the
location arrow to confirm.

## Project layout

```
ios-fake-gps/
├── macapp/                     native macOS app (Swift Package, SwiftUI + MapKit)
│   ├── Package.swift
│   └── Sources/FakeGPS/
│       ├── App.swift            app entry point + dependency wiring
│       ├── ContentView.swift    sidebar controls, search, transport
│       ├── MapView.swift        MKMapView wrapper (waypoints, route, marker)
│       ├── MapController.swift   map commands + MapKit place search
│       ├── SimulationEngine.swift  route interpolation, play/pause/loop/jitter
│       ├── Sidecar.swift        launches & speaks JSON to the Python helper
│       ├── TunnelManager.swift  tracks / starts the root tunnel daemon
│       ├── Geo.swift            haversine + along-path interpolation maths
│       └── AppConfig.swift      resolves the runtime location
├── sidecar/
│   ├── gpsd_helper.py          persistent location-simulation helper
│   └── requirements.txt
└── docs/                       screenshots
```

## Building the release app yourself

To produce the same bundled `FakeGPS.app` that's on the Releases page:

```bash
./scripts/build_runtime.sh   # freezes the Python engine into a standalone binary
./scripts/build_app.sh       # builds the Swift app and assembles FakeGPS.app + a zip
```

Output lands in `dist/`:

```
dist/FakeGPS.app                  ← double-clickable app, runtime bundled inside
dist/FakeGPS-macos-arm64.zip      ← what gets attached to a release
```

The build needs the dev sidecar set up first (see setup above) plus PyInstaller
(`~/.ios-fake-gps/venv/bin/python -m pip install pyinstaller`). Builds are
per-architecture; run it on an Apple-silicon Mac for an `arm64` build.

## Troubleshooting

- **"Tunnel daemon not running"** — start `tunneld` (needs `sudo`); confirm with
  `curl http://127.0.0.1:49151`.
- **`PermissionError: ... pyvenv.cfg`** — the venv is under a TCC-protected
  folder. Recreate it in `~/.ios-fake-gps` as shown above.
- **"Could not open LocationSimulation … DDI"** — Developer Mode is off, the
  device isn't trusted, or the Developer Disk Image hasn't mounted yet. Re-plug,
  trust, and give `tunneld` a few seconds to auto-mount it.
- **No device listed** — check with
  `~/.ios-fake-gps/venv/bin/pymobiledevice3 usbmux list`.
- **App can't find the sidecar** — it looks in `~/.ios-fake-gps`; the connection
  panel warns if it can't find `venv/bin/python` + `gpsd_helper.py`.

## Limitations

- The Mac must stay tethered (USB; Wi-Fi works after an initial USB pairing).
- iOS 17+ requires Developer Mode and the root `tunneld` daemon.
- This sets the reported location; it does not fake Wi-Fi or cell-tower signals,
  so a small number of apps that cross-check those may notice the mismatch.

## Built with

- [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) — the developer
  tunnel and `LocationSimulation` service.
- SwiftUI + MapKit for the macOS app.
