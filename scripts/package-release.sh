#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh --notarize
APP=infravibe.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
OUTPUT="$PWD/dist/$VERSION"
SIGNING_IDENTITY="Developer ID Application: Doug Dowenr (J77629PP5S)"
IDENTITY_CHANGE_BUILD=18  # first build with com.dynadobe.infravibe
RELEASE_URL="https://github.com/netsecdevio/infravibe/releases/download/v$VERSION"
# Each feed must describe exactly the signed archive produced by this invocation.
if [[ -e "$OUTPUT" ]]; then
    echo "Release output already exists: $OUTPUT. Move it aside before rebuilding." >&2
    exit 1
fi
mkdir -p "$OUTPUT"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/infravibe.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUTPUT/infravibe-$VERSION.dmg"
hdiutil create -volname "infravibe $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG"
codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile InfraProxy --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
hdiutil verify "$DMG"
python3 - "$OUTPUT/infravibe-$VERSION.html" <<'PY'
import html, pathlib, sys
notes = pathlib.Path('RELEASE_NOTES.md').read_text()
pathlib.Path(sys.argv[1]).write_text('<pre>' + html.escape(notes) + '</pre>')
PY
Vendor/Sparkle/bin/generate_appcast --account com.dynadobe.infraproxy \
    --maximum-deltas 0 --embed-release-notes --download-url-prefix "$RELEASE_URL/" \
    --link "https://github.com/netsecdevio/infravibe/releases/tag/v$VERSION" "$OUTPUT"
# Builds before the 2.13.0 bundle-ID change (com.dynadobe.infraproxy) cannot install this archive in place.
# Mark the item informational for them so Sparkle links to the release page instead of attempting an install.
python3 - "$OUTPUT/appcast.xml" "$IDENTITY_CHANGE_BUILD" <<'PY'
import pathlib, re, sys
path, below = pathlib.Path(sys.argv[1]), sys.argv[2]
text = path.read_text()
text = re.sub(r'\n?<!-- sparkle-signatures:.*?-->\n?', '\n', text, flags=re.S)  # re-signed below
info = f'<sparkle:informationalUpdate><sparkle:belowVersion>{below}</sparkle:belowVersion></sparkle:informationalUpdate>'
assert text.count('<item>') == 1 and '<sparkle:informationalUpdate>' not in text
path.write_text(text.replace('</item>', f'    {info}\n        </item>', 1))
PY
Vendor/Sparkle/bin/sign_update --account com.dynadobe.infraproxy "$OUTPUT/appcast.xml"
Vendor/Sparkle/bin/sign_update --account com.dynadobe.infraproxy --verify "$OUTPUT/appcast.xml"
(cd "$OUTPUT" && shasum -a 256 "infravibe-$VERSION.dmg" > "infravibe-$VERSION.dmg.sha256")
echo "Ready to publish: $OUTPUT"
echo "Upload the DMG, checksum, and appcast.xml together; then mark the release latest."
