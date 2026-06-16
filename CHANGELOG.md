# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.0] - 2026-06-16

### Added
- GitHub Actions: CI build check on every push/PR, and a tag-triggered workflow
  that builds the app on a macOS runner and attaches it to the release.
- Open-source project files: MIT license, contributing guide, code of conduct,
  security policy, disclaimer, and issue/PR templates.

### Changed
- Hardened Swift concurrency so the app builds cleanly under stricter toolchains
  (no behaviour change).

## [0.2.0] - 2026-06-15

### Added
- App icon — an Apple-style squircle with a location pin and signal pulses.
- In-app onboarding checklist that detects a connected iPhone, starts the tunnel,
  and connects you, so no documentation or Terminal is needed.
- Live USB device detection (a `usbmux` runtime mode).
- Auto-reset to real GPS when disconnecting or quitting the app.

### Changed
- Rewrote the README around downloading and using the app.
- Unified the development and bundled runtimes behind one entry point.

## [0.1.0] - 2026-06-15

### Added
- Native macOS app (SwiftUI + MapKit): teleport, route playback with adjustable
  speed, looping, GPS jitter, and address search.
- Python engine built on pymobiledevice3, frozen into a standalone binary and
  bundled inside the app — no Python install required.
- One-click tunnel daemon launch and packaged, double-clickable `FakeGPS.app`.

[0.3.0]: https://github.com/orestislef/ios-fake-gps/releases/tag/v0.3.0
[0.2.0]: https://github.com/orestislef/ios-fake-gps/releases/tag/v0.2.0
[0.1.0]: https://github.com/orestislef/ios-fake-gps/releases/tag/v0.1.0
