#!/bin/sh
# Builds build/Markup.app: a release build of the executable, Info.plist and
# the app icon generated from img/Markup.png, and Sparkle.framework.
set -eu

cd "$(dirname "$0")/.."

app=build/Markup.app
iconset=build/AppIcon.iconset

# UNIVERSAL=1 builds for Apple silicon and Intel, as releases are.
if [ -n "${UNIVERSAL:-}" ]; then
    arch="--arch arm64 --arch x86_64"
else
    arch=""
fi
swift build -c release $arch
bin="$(swift build -c release $arch --show-bin-path)"

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
