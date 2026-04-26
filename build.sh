#!/usr/bin/env bash
# Build, sign, notarize, and package the Nerdymark ScreenSaver for distribution.
#
# Prereqs (one-time):
#   brew install xcodegen create-dmg
#   xcrun notarytool store-credentials "nerdymark-notary" \
#     --apple-id "you@example.com" \
#     --team-id "YOURTEAMID" \
#     --password "app-specific-password"
#
# Per-build config — set these env vars or a local .env file alongside this script:
#   DEVELOPMENT_TEAM      Apple Developer team ID (10-char string)
#   SIGNING_IDENTITY      "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE        keychain profile name used in `notarytool store-credentials`
#
# Usage:
#   ./build.sh                   # full pipeline: build → sign → notarize → dmg
#   ./build.sh --no-notarize     # build + sign + dmg (for local testing)
#   ./build.sh --clean           # wipe build/ first

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env if present (allows personal config without committing it).
if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    source .env
fi

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM in .env or env (10-char Apple team ID)}"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY in .env (e.g., 'Developer ID Application: Your Name (TEAMID)')}"
: "${NOTARY_PROFILE:=nerdymark-notary}"

SKIP_NOTARIZE=0
CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --no-notarize) SKIP_NOTARIZE=1 ;;
        --clean)       CLEAN=1 ;;
        *)             echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

# iCloud Drive auto-adds xattrs (FinderInfo, metadata) to every file in
# its sync tree. codesign refuses to sign anything carrying those xattrs.
# Keep build artifacts on a plain local path so the bundle stays clean.
BUILD_ROOT="${BUILD_ROOT:-$HOME/Library/Developer/Xcode/DerivedData/NerdymarkScreenSaver}"
BUILD_DIR="$BUILD_ROOT/build"
DIST_DIR="$BUILD_ROOT/dist"
SAVER_NAME="NerdymarkScreenSaver.saver"

if [[ "$CLEAN" == "1" ]]; then
    echo "==> Cleaning build/ and dist/"
    rm -rf "$BUILD_DIR" "$DIST_DIR"
fi

mkdir -p "$BUILD_DIR" "$DIST_DIR"

# --- 0. Strip iCloud/Finder xattrs from source files ---
# iCloud marks every file it syncs; codesign refuses to sign resources
# carrying those attributes even when copied to a clean build dir.
echo "==> Stripping xattrs from source tree"
xattr -cr Sources Resources 2>/dev/null || true

# --- 1. Generate Xcode project ---
echo "==> Generating Xcode project (xcodegen)"
command -v xcodegen >/dev/null || { echo "xcodegen not installed — 'brew install xcodegen'"; exit 1; }
xcodegen generate --spec project.yml

# --- 2. Build Release ---
echo "==> Building Release (universal)"
xcodebuild \
    -project NerdymarkScreenSaver.xcodeproj \
    -scheme NerdymarkScreenSaver \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build | xcpretty 2>/dev/null || xcodebuild \
        -project NerdymarkScreenSaver.xcodeproj \
        -scheme NerdymarkScreenSaver \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
        CODE_SIGN_STYLE=Manual \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        build

BUILT_SAVER="$BUILD_DIR/DerivedData/Build/Products/Release/$SAVER_NAME"
if [[ ! -d "$BUILT_SAVER" ]]; then
    echo "Expected product not found at $BUILT_SAVER" >&2
    exit 1
fi

# Copy to dist/ so we don't mutate the xcodebuild output.
DIST_SAVER="$DIST_DIR/$SAVER_NAME"
rm -rf "$DIST_SAVER"
cp -R "$BUILT_SAVER" "$DIST_SAVER"

# --- 3. Verify signature ---
echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$DIST_SAVER"

# --- 4. Notarize ---
if [[ "$SKIP_NOTARIZE" == "0" ]]; then
    NOTARIZE_ZIP="$BUILD_DIR/${SAVER_NAME%.saver}-notarize.zip"
    rm -f "$NOTARIZE_ZIP"
    echo "==> Zipping for notarization"
    ( cd "$DIST_DIR" && /usr/bin/ditto -c -k --keepParent "$SAVER_NAME" "$NOTARIZE_ZIP" )

    echo "==> Submitting to notarytool (profile: $NOTARY_PROFILE)"
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$DIST_SAVER"
    xcrun stapler validate "$DIST_SAVER"
else
    echo "==> Skipping notarization (--no-notarize)"
fi

# --- 5. Build DMG ---
DMG_PATH="$DIST_DIR/NerdymarkScreenSaver.dmg"
rm -f "$DMG_PATH"

echo "==> Creating DMG"
if command -v create-dmg >/dev/null; then
    create-dmg \
        --volname "Nerdymark ScreenSaver" \
        --window-size 540 340 \
        --icon-size 96 \
        --icon "$SAVER_NAME" 140 160 \
        --hide-extension "$SAVER_NAME" \
        --app-drop-link 400 160 \
        "$DMG_PATH" \
        "$DIST_SAVER" 2>/dev/null || {
            # create-dmg can fail on icon positioning if Finder isn't cooperative;
            # fall back to hdiutil which always works.
            echo "   create-dmg failed, falling back to hdiutil"
            hdiutil create -volname "Nerdymark ScreenSaver" \
                -srcfolder "$DIST_SAVER" \
                -ov -format UDZO "$DMG_PATH"
        }
else
    echo "   create-dmg not installed, using hdiutil"
    hdiutil create -volname "Nerdymark ScreenSaver" \
        -srcfolder "$DIST_SAVER" \
        -ov -format UDZO "$DMG_PATH"
fi

# Sign + notarize the DMG too — optional but gives a cleaner Gatekeeper
# experience when users double-click it.
if [[ "$SKIP_NOTARIZE" == "0" ]]; then
    echo "==> Signing DMG"
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$DMG_PATH"

    echo "==> Notarizing DMG"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    xcrun stapler staple "$DMG_PATH"
fi

SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo ""
echo "✓ Done. $DMG_PATH ($SIZE)"
echo ""
echo "  Next: copy the DMG into the site's static/downloads/ (outside iCloud"
echo "  would re-add xattrs anyway, so cp strips them on the way in):"
echo ""
echo "    cp \"$DMG_PATH\" ../static/downloads/NerdymarkScreenSaver.dmg"
echo "    xattr -c ../static/downloads/NerdymarkScreenSaver.dmg"
echo ""
