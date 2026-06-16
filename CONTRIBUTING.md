# Contributing

Thanks for your interest in improving iOS Fake GPS! Contributions of all kinds
are welcome — bug reports, fixes, features and docs.

## Ground rules

- Be respectful; see the [Code of Conduct](CODE_OF_CONDUCT.md).
- This project is for lawful use only; please don't propose features whose main
  purpose is to deceive third parties or defeat security/anti-fraud systems (see
  the [Disclaimer](DISCLAIMER.md)).

## Project layout

```
macapp/Sources/FakeGPS/   the macOS app (SwiftUI + MapKit)
sidecar/                  the Python engine + runtime entry point
scripts/                  build_runtime.sh, build_app.sh, make_icon.py
assets/                   app icon
docs/                     screenshots
```

## Development setup

Requirements: macOS on Apple silicon, Xcode / Swift toolchain, Python 3.10+.

```bash
# one-time: set up the Python engine in ~/.ios-fake-gps
./setup.sh

# run the app from source
cd macapp && swift run
```

To start the developer tunnel while testing from source:

```bash
sudo ~/.ios-fake-gps/venv/bin/python ~/.ios-fake-gps/fakegps_runtime.py tunneld
```

## Building the release artifact

```bash
./scripts/build_app.sh     # -> dist/FakeGPS.app and dist/FakeGPS-macos-arm64.zip
```

CI builds the same artifact automatically when a `v*` tag is pushed.

## Pull requests

1. Fork and create a branch from `main`.
2. Keep changes focused; match the surrounding code style.
3. Make sure `cd macapp && swift build` succeeds.
4. Describe what you changed and how you tested it.

## Reporting bugs

Open an issue using the templates. Include your macOS version, Mac model
(e.g. M1/M4), iPhone model and iOS version, and any relevant output from
`/tmp/ios-fake-gps-tunneld.log`.
