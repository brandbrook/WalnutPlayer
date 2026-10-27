#!/bin/bash
#
# Builds a Walnut release: archive, Developer ID export, notarization, stapling, zip,
# Sparkle signature and a new appcast.xml entry. Nothing is uploaded; see RELEASING.md.
#
# Needs: Xcode, the Developer ID certificate, the notarytool keychain profile
# (NOTARY_PROFILE, default walnut-notary) and the Sparkle EdDSA key in the login keychain.

set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-walnut-notary}"
SPARKLE_VERSION=2.10.0
REPO=brandbrook/WalnutPlayer
PLIST=Resources/Hermes-Info.plist

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")
ZIP="build/Walnut-$VERSION.zip"
APP=build/export/Walnut.app

info() { echo ">>> $*"; }

info "Walnut $VERSION ($BUILD)"
if grep -q "<sparkle:version>$BUILD</sparkle:version>" appcast.xml 2>/dev/null; then
  echo "appcast.xml already has build $BUILD. Raise CFBundleVersion first." >&2; exit 1
fi

info "Archiving"
rm -rf build/Walnut.xcarchive build/export
xcodebuild -project Hermes.xcodeproj -scheme Hermes -configuration Release \
  -archivePath build/Walnut.xcarchive archive -quiet

info "Exporting with Developer ID"
xcodebuild -exportArchive -archivePath build/Walnut.xcarchive -exportPath build/export \
  -exportOptionsPlist Scripts/ExportOptions.plist -quiet

# Leave extended attributes out of the zip: macOS 26 tags every file, ditto stores the tags as
# "._" files, and older macOS unpacks those next to the framework symlinks, breaking the seal.
zipapp() { rm -f "$ZIP"; ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" "$ZIP"; }

info "Notarizing (this takes a few minutes)"
zipapp
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
zipapp
if zipinfo -1 "$ZIP" | grep -q '/\._'; then echo "$ZIP has ._ files." >&2; exit 1; fi
spctl -a -vv "$APP"
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$APP/Contents/Info.plist")

info "Signing for Sparkle"
TOOLS=build/sparkle-tools
if [ ! -x "$TOOLS/bin/sign_update" ]; then
  mkdir -p "$TOOLS"
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJ -C "$TOOLS"
fi
SIGNATURE=$("$TOOLS/bin/sign_update" "$ZIP")   # sparkle:edSignature="…" length="…"

info "Adding $VERSION to appcast.xml"
ITEM="    <item>
      <title>Walnut $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url=\"https://github.com/$REPO/releases/download/v$VERSION/Walnut-$VERSION.zip\" type=\"application/octet-stream\" $SIGNATURE/>
    </item>"
if [ ! -f appcast.xml ]; then
  cat > appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Walnut</title>
    <link>https://github.com/$REPO</link>
    <language>en</language>
  </channel>
</rss>
EOF
fi
# newest first, right after <language>
ITEM="$ITEM" perl -0pi -e 's#(<language>en</language>\n)#$1$ENV{ITEM}\n#' appcast.xml

info "Done: $ZIP"
info "Next: commit appcast.xml, push, then publish release v$VERSION with $ZIP attached (see RELEASING.md)."
