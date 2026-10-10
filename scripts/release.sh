#!/bin/sh
# Builds a release of the version in project.yml: signs it with a Developer ID, has Apple notarize it,
# packs it in a disk image and writes the update feed. With "publish" it then tags the release and puts it on GitHub.
#
#   ./scripts/release.sh            build, sign, notarize, update appcast.xml; everything lands in dist/
#   ./scripts/release.sh publish    the same, then commit appcast.xml, tag, push and create the GitHub release
#
# QB_SKIP_NOTARIZE=1 leaves out notarization, for when there is no active Apple Developer membership.
# People then have to approve the app in System Settings the first time they open it.
#
# Needs: a "Developer ID Application" certificate in the keychain, a notarytool profile
# (xcrun notarytool store-credentials queenbee-notary), the Sparkle update key in the keychain
# (generate_keys --account queen-bee), and gh signed in.
set -eu
cd "$(dirname "$0")/.."

REPO="${QB_REPO:-bamboozledkitty/queen-bee}"
IDENTITY="${QB_SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${QB_NOTARY_PROFILE:-queenbee-notary}"
SPARKLE_ACCOUNT="${QB_SPARKLE_ACCOUNT:-queen-bee}"

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
TAG="v$VERSION"
APP=build/Build/Products/Release/QueenBee.app
OUT="dist/$VERSION"
DMG="$OUT/QueenBee-$VERSION.dmg"
SPARKLE=build/SourcePackages/artifacts/sparkle/Sparkle/bin

grep -q "^## \[$VERSION\]" CHANGELOG.md || { echo "CHANGELOG.md has no section for $VERSION"; exit 1; }
if git rev-parse "$TAG" >/dev/null 2>&1; then echo "$TAG already exists. Raise MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml."; exit 1; fi

echo "== Building $VERSION"
xcodegen generate --quiet
# An app left by an earlier build must never be mistaken for this one, so it is removed first
# and the build has to say it succeeded.
rm -rf "$APP"
BUILD_LOG=$(mktemp)
xcodebuild -project QueenBee.xcodeproj -scheme QueenBee -configuration Release \
  -derivedDataPath build -skipPackagePluginValidation -skipMacroValidation build > "$BUILD_LOG" 2>&1 || true
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$BUILD_LOG" || true
grep -q "BUILD SUCCEEDED" "$BUILD_LOG" || { echo "The release build failed. Nothing was packaged."; rm -f "$BUILD_LOG"; exit 1; }
rm -f "$BUILD_LOG"
[ -d "$APP" ] || { echo "The build didn't produce $APP"; exit 1; }
BUILT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
[ "$BUILT" = "$VERSION" ] || { echo "The built app says $BUILT, not $VERSION"; exit 1; }

echo "== Signing"
# Inside out: Sparkle's helpers, the framework, our helper, then the app.
sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
sign "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
sign "$FRAMEWORK/Versions/B/Autoupdate"
sign "$FRAMEWORK/Versions/B/Updater.app"
sign "$FRAMEWORK"
sign "$APP/Contents/MacOS/qb"
sign "$APP"
codesign --verify --deep --strict "$APP"

if [ "${QB_SKIP_NOTARIZE:-}" = "1" ]; then
  echo "== Skipping notarization (QB_SKIP_NOTARIZE=1)"
  notarize() { :; }
  staple() { :; }
  assess() { :; }
else
  notarize() { xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait; }
  staple() { xcrun stapler staple "$1"; }
  assess() { spctl --assess "$@"; }
fi

echo "== Notarizing the app"
# The app first, so the copy people drag out of the disk image carries its own ticket and opens offline.
rm -rf "$OUT" && mkdir -p "$OUT"
ditto -c -k --keepParent "$APP" "$OUT/app.zip"
notarize "$OUT/app.zip"
rm "$OUT/app.zip"
staple "$APP"
assess --type execute -vv "$APP"

echo "== Building the disk image"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Queen Bee" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
staple "$DMG"
assess --type open --context context:primary-signature -vv "$DMG"

echo "== Writing the update feed"
# The notes for this version are its section of the changelog.
awk -v v="$VERSION" '/^## \[/{on = index($0, "[" v "]") > 0; next} /^\[.*\]: /{on = 0} on' CHANGELOG.md > "$OUT/QueenBee-$VERSION.md"
cp appcast.xml "$OUT/appcast.xml" 2>/dev/null || true
"$SPARKLE/generate_appcast" --account "$SPARKLE_ACCOUNT" --embed-release-notes \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --link "https://github.com/$REPO" -o "$OUT/appcast.xml" "$OUT"
cp "$OUT/appcast.xml" appcast.xml
echo "Built $DMG"

[ "${1:-}" = "publish" ] || { echo "Run again with 'publish' to release it."; exit 0; }

echo "== Publishing $TAG"
git add appcast.xml
git commit -q -m "Release $TAG" -- appcast.xml
git tag "$TAG"
git push -q origin HEAD "$TAG"
gh release create "$TAG" "$DMG" --repo "$REPO" --title "Queen Bee $VERSION" --notes-file "$OUT/QueenBee-$VERSION.md"
