#!/bin/sh
# Package the SwiftPM executable as dist/Sill.app (ad-hoc signed).
set -eu
cd "$(dirname "$0")"

swift build -c release 2>&1 | tail -3
BIN="$(swift build -c release --show-bin-path)/Sill"
ROOT="$(cd ../.. && pwd)"
APP="$ROOT/dist/Sill.app"

# Ship the `sill` CLI inside the app — panes add it to PATH at spawn.
# No `| tail` on the build: set -e must see cargo's real exit status, else a
# failed build would silently ship the previous release binary.
# --target-dir keeps the copy source correct even with CARGO_TARGET_DIR set.
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"
[ "${TARGET_DIR#/}" = "$TARGET_DIR" ] && TARGET_DIR="$PWD/$TARGET_DIR"
cargo build --release -p sill --manifest-path "$ROOT/Cargo.toml" --target-dir "$TARGET_DIR"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp "$BIN" "$APP/Contents/MacOS/Sill"
# `sill` can't sit next to `Sill` (case-insensitive APFS) — it goes in bin/.
cp "$TARGET_DIR/release/sill" "$APP/Contents/Resources/bin/sill"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.sill.app</string>
    <key>CFBundleName</key><string>Sill</string>
    <key>CFBundleDisplayName</key><string>Sill</string>
    <key>CFBundleExecutable</key><string>Sill</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSUserNotificationUsageDescription</key><string>Sill notifies you when an agent is waiting for input while the window is hidden.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS will run it locally.
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "built $APP"
