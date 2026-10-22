#!/bin/sh
# Makes a release: a universal build/Markup.app signed with a Developer ID and
# the hardened runtime, in build/Markup-<version>.dmg (the app beside a link
# to Applications), notarized and stapled, for people to download. Then the
# stapled app zipped into build/releases/<version>/Markup-<version>.zip, from
# which Sparkle updates, and its entry added to appcast.xml, signed with the
# EdDSA key in the login keychain (made once with
# `.build/artifacts/sparkle/Sparkle/bin/generate_keys`, whose public key goes
# in Info.plist as SUPublicEDKey).
#
#   scripts/release.sh            Developer ID signing and notarization
#   scripts/release.sh --adhoc    local signature only, to test the packaging;
#                                 the appcast is left alone
#
# Environment:
#   SIGN_IDENTITY    codesign identity; defaults to the first "Developer ID
#                    Application" in the keychain
#   NOTARY_PROFILE   notarytool keychain profile (default: listful-notary,
#                    which is the same Apple ID and team), made once with
#                    xcrun notarytool store-credentials <name> --apple-id <id> --team-id <team>
#
# Then upload the zip and the DMG to a GitHub release tagged v<version>, and
# commit and push appcast.xml, which is the feed Info.plist's SUFeedURL names.
#
# Bump CFBundleShortVersionString and CFBundleVersion in Info.plist first:
# Sparkle compares CFBundleVersion.
set -eu

cd "$(dirname "$0")/.."

adhoc=false
[ "${1:-}" = "--adhoc" ] && adhoc=true

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
key=$(/usr/libexec/PlistBuddy -c "Print SUPublicEDKey" Info.plist)
if [ -z "$key" ]; then
    echo "Info.plist has no SUPublicEDKey. Run generate_keys and add its public key." >&2
    exit 1
fi

if $adhoc; then
    identity=-
else
    identity=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning |
        sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -n 1)}
    if [ -z "$identity" ]; then
        echo "No \"Developer ID Application\" certificate in the keychain. Set SIGN_IDENTITY or use --adhoc." >&2
        exit 1
    fi
fi
profile=${NOTARY_PROFILE:-listful-notary}

step() { printf '\n==> %s\n' "$*"; }

step "Markup $version, signing as: $identity"
UNIVERSAL=1 scripts/build-app.sh
app=build/Markup.app
fw="$app/Contents/Frameworks/Sparkle.framework"

step "Signing (hardened runtime)"
# The hardened runtime only loads a framework signed by the app's team,
# which ad-hoc signatures have none of.
if $adhoc; then
    sign() { codesign --force --sign - "$@"; }
else
    sign() { codesign --force --options runtime --timestamp --sign "$identity" "$@"; }
fi
# Sparkle's XPC services are only for sandboxed apps, which Markup isn't.
rm -rf "$fw/XPCServices" "$fw/Versions/B/XPCServices"
# Inside out: Sparkle's helpers, the framework, then the app.
sign "$fw/Versions/B/Autoupdate"
sign "$fw/Versions/B/Updater.app"
sign "$fw"
sign "$app"
codesign --verify --strict --verbose=2 "$app"

# The DMG is kept out of the releases folder, which generate_appcast reads.
dmg="build/Markup-$version.dmg"
step "Creating $dmg"
staging=build/dmg
rm -rf "$staging" "$dmg"
mkdir -p "$staging"
ditto "$app" "$staging/Markup.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Markup $version" -srcfolder "$staging" -fs HFS+ -format UDZO -quiet "$dmg"
rm -rf "$staging"

if $adhoc; then
    step "Ad-hoc build done: not notarized, so Gatekeeper blocks it on other Macs"
    exit 0
fi

codesign --force --timestamp --sign "$identity" "$dmg"

step "Notarizing (usually a few minutes)"
result=$(xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait 2>&1) || true
echo "$result"
if ! echo "$result" | grep -q "status: Accepted"; then
    id=$(echo "$result" | sed -n 's/^ *id: //p' | head -n 1)
    echo "Notarization failed. Details: xcrun notarytool log $id --keychain-profile $profile" >&2
    exit 1
fi

step "Stapling"
# Notarizing the DMG notarizes the app in it too, so both take the ticket.
xcrun stapler staple "$dmg"
xcrun stapler staple "$app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
spctl --assess --type execute --verbose=2 "$app"

releases=build/releases/$version
step "Zipping the app for Sparkle into $releases"
mkdir -p "$releases"
rm -f "$releases"/*.zip
zip="$releases/Markup-$version.zip"
ditto -c -k --keepParent "$app" "$zip"

.build/artifacts/sparkle/Sparkle/bin/generate_appcast "$releases" \
    --download-url-prefix "https://github.com/drchrispinnock/markup/releases/download/v$version/" \
    -o appcast.xml

step "Done: $dmg, $zip and appcast.xml"
