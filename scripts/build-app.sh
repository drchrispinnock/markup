#!/bin/sh
# Builds build/Markup.app: a release build of the executable, Info.plist and
# the app icon generated from img/Markup.png.
set -eu

cd "$(dirname "$0")/.."

app=build/Markup.app
iconset=build/AppIcon.iconset

swift build -c release
binary="$(swift build -c release --show-bin-path)/Markup"

rm -rf "$app" "$iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

swift scripts/make-icon.swift img/Markup.png "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$iconset"

cp "$binary" "$app/Contents/MacOS/Markup"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"

echo "Built $app"
