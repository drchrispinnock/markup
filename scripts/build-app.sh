#!/bin/sh
# Builds build/Markup.app: a release build of the executable, Info.plist and
# the app icon generated from img/Markup.png, and Sparkle.framework.
set -eu

cd "$(dirname "$0")/.."

app=build/Markup.app
iconset=build/AppIcon.iconset

swift build -c release
bin="$(swift build -c release --show-bin-path)"

rm -rf "$app" "$iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"

swift scripts/make-icon.swift img/Markup.png "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$iconset"

cp "$bin/Markup" "$app/Contents/MacOS/Markup"
cp Info.plist "$app/Contents/Info.plist"
# ditto keeps the framework's symlinks. Sparkle signed it already, so only
# the app is signed here.
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$app"

echo "Built $app"
