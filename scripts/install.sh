#!/bin/sh
# Installs the latest Queen Bee release into /Applications, from a terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/bamboozledkitty/queen-bee/main/scripts/install.sh | sh
#
# Releases are signed with a Developer ID but not yet notarized by Apple, so a copy downloaded in a
# browser has to be approved in System Settings. A copy fetched here isn't marked as a browser download,
# so it opens straight away. In place of Apple's check, this script refuses anything that isn't signed
# by the Queen Bee developer's certificate.
#
# QB_INSTALL_DIR puts the app somewhere other than /Applications.
set -eu

REPO="bamboozledkitty/queen-bee"
TEAM="M76T8VT55M"
DEST_DIR="${QB_INSTALL_DIR:-/Applications}"
DEST="$DEST_DIR/QueenBee.app"

fail() { echo "install: $1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Queen Bee only runs on macOS."
[ "$(uname -m)" = "arm64" ] || fail "Queen Bee needs a Mac with Apple silicon."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ] || fail "Queen Bee needs macOS 26 or later."
[ -d "$DEST_DIR" ] && [ -w "$DEST_DIR" ] || fail "can't write to $DEST_DIR."
if [ "$DEST_DIR" = "/Applications" ] && pgrep -x QueenBee >/dev/null; then
  fail "Queen Bee is open. Quit it, then run this again."
fi

WORK=$(mktemp -d)
MOUNT="$WORK/mount"
cleanup() {
  hdiutil detach -quiet "$MOUNT" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "Finding the latest release..."
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | sed -n 's/.*"browser_download_url": *"\(https:[^"]*\.dmg\)".*/\1/p' | head -1)
[ -n "$URL" ] || fail "couldn't find a release to download."

echo "Downloading $(basename "$URL")..."
curl -fL --progress-bar -o "$WORK/QueenBee.dmg" "$URL"

mkdir "$MOUNT"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$WORK/QueenBee.dmg" >/dev/null 2>&1 \
  || fail "couldn't open the download."
[ -d "$MOUNT/QueenBee.app" ] || fail "the download doesn't contain Queen Bee."

echo "Checking the signature..."
codesign --verify --deep --strict "$MOUNT/QueenBee.app" 2>/dev/null || fail "the app's signature is broken. Nothing was installed."
SIGNER=$(codesign -dv "$MOUNT/QueenBee.app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ "$SIGNER" = "$TEAM" ] || fail "the app is signed by someone else ($SIGNER). Nothing was installed."

echo "Installing to $DEST..."
rm -rf "$DEST.new"
ditto "$MOUNT/QueenBee.app" "$DEST.new"
rm -rf "$DEST"
mv "$DEST.new" "$DEST"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DEST/Contents/Info.plist")
echo "Queen Bee $VERSION is installed. Open it from $DEST_DIR, or run: open \"$DEST\""
