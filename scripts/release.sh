#!/bin/sh
# Makes a release for Sparkle: builds build/Markup.app, zips it into
# build/releases/<version>/Markup-<version>.zip, and adds an entry for it to
# appcast.xml, signed with the EdDSA key in the login keychain
# (made once with `.build/artifacts/sparkle/Sparkle/bin/generate_keys`,
# whose public key goes in Info.plist as SUPublicEDKey).
#
# Then upload the zip to a GitHub release tagged v<version>, and commit and
# push appcast.xml, which is the feed Info.plist's SUFeedURL names.
#
# Bump CFBundleShortVersionString and CFBundleVersion in Info.plist first:
# Sparkle compares CFBundleVersion.
set -eu

cd "$(dirname "$0")/.."

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
key=$(/usr/libexec/PlistBuddy -c "Print SUPublicEDKey" Info.plist)
if [ -z "$key" ]; then
    echo "Info.plist has no SUPublicEDKey. Run generate_keys and add its public key." >&2
    exit 1
fi

scripts/build-app.sh

releases=build/releases/$version
mkdir -p "$releases"
zip="$releases/Markup-$version.zip"
rm -f "$releases"/*.zip
ditto -c -k --keepParent build/Markup.app "$zip"

.build/artifacts/sparkle/Sparkle/bin/generate_appcast "$releases" \
    --download-url-prefix "https://github.com/drchrispinnock/markup/releases/download/v$version/" \
    -o appcast.xml

echo "Made $zip and appcast.xml"
