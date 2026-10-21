#!/bin/zsh
# Builds SlapGlitch.app next to this script.
set -e
cd "$(dirname "$0")"
APP=SlapGlitch.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS
swiftc -O -swift-version 5 -target arm64-apple-macos14 Accel.swift main.swift -o $APP/Contents/MacOS/SlapGlitch
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.daniilpak.slapglitch</string>
  <key>CFBundleName</key><string>SlapGlitch</string>
  <key>CFBundleExecutable</key><string>SlapGlitch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>SlapGlitch captures the screen so a slap can tear it apart.</string>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "Built $PWD/$APP"
