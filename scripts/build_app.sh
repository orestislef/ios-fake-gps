#!/usr/bin/env bash
#
# Build a distributable, double-clickable FakeGPS.app with the Python runtime
# bundled inside it, then zip it for a GitHub release.
#
# Output:
#   dist/FakeGPS.app
#   dist/FakeGPS-macos-arm64.zip
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
APP="$REPO/dist/FakeGPS.app"
ARCH="$(uname -m)"

cd "$REPO"

if [ "${SKIP_RUNTIME:-0}" = "1" ] && [ -x dist_pyi/fakegps-runtime/fakegps-runtime ]; then
  echo "==> 1/6  Reusing existing frozen runtime (SKIP_RUNTIME=1)"
else
  echo "==> 1/6  Freezing the Python runtime"
  ./scripts/build_runtime.sh >/dev/null
fi
test -x dist_pyi/fakegps-runtime/fakegps-runtime

echo "==> 2/6  Building the macOS app (release)"
( cd macapp && swift build -c release >/dev/null )
SWIFT_BIN="$(cd macapp && swift build -c release --show-bin-path)/FakeGPS"
test -x "$SWIFT_BIN"

echo "==> 3/6  Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/runtime"
cp "$SWIFT_BIN" "$APP/Contents/MacOS/FakeGPS"
cp -R dist_pyi/fakegps-runtime/. "$APP/Contents/Resources/runtime/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FakeGPS</string>
  <key>CFBundleDisplayName</key><string>iOS Fake GPS</string>
  <key>CFBundleExecutable</key><string>FakeGPS</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>io.github.orestislef.ios-fake-gps</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> 4/6  Compiling AppIcon.icon"

xcrun actool "$REPO/assets/AppIcon.icon" \
  --compile "$APP/Contents/Resources" \
  --platform macosx \
  --target-device mac \
  --minimum-deployment-target 14.0 \
  --lightweight-asset-runtime-mode=enabled \
  --app-icon AppIcon \
  --output-partial-info-plist "$APP/Contents/icon-info.plist" \
  --output-format human-readable-text \
  --warnings \
  --errors \
  --notices

test -s "$APP/Contents/Resources/Assets.car"
test -s "$APP/Contents/Resources/AppIcon.icns"

plutil -p "$APP/Contents/icon-info.plist"
rm "$APP/Contents/icon-info.plist"

echo "==> 5/6  Ad-hoc code signing"
# Unsigned downloads are Gatekeeper-quarantined; ad-hoc signing lets it run
# locally after the user clears quarantine (right-click > Open).
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "    (codesign skipped/failed — app still runs after clearing quarantine)"

echo "==> 6/6  Zipping for release"
ZIP="$REPO/dist/FakeGPS-macos-${ARCH}.zip"
rm -f "$ZIP"
( cd "$REPO/dist" && ditto -c -k --sequesterRsrc --keepParent FakeGPS.app "$ZIP" )

echo
echo "Done:"
echo "  $APP"
echo "  $ZIP"
du -sh "$ZIP" | awk '{print "  size: "$1}'
