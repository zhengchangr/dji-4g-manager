#!/bin/sh
# DJI 4G Manager release packaging script
#
# Local test package (default):
#   ./scripts/package-release.sh
#
# Official distribution (requires Apple Developer ID certificate):
#   IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-release.sh
#
# Notarization (requires developer account):
#   xcrun notarytool submit dist/DJI4GManager-Release/DJI4GManager-Release.zip \
#     --keychain-profile "notary" --wait
#   xcrun stapler staple dist/DJI4GManager-Release/DJI4GManager-Release.zip
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${CONFIGURATION:-Release}
IDENTITY=${IDENTITY:--}
DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/$CONFIGURATION/DJI4GManager.app"
OUT="$ROOT/dist/DJI4GManager-$CONFIGURATION"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Building $CONFIGURATION"
DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
  -project "$ROOT/DJI4GManager.xcodeproj" \
  -scheme DJI4GManager \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  MACOSX_DEPLOYMENT_TARGET=15.0 \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  build

echo "==> Copying app"
cp -R "$APP" "$OUT/"

echo "==> Signing (${IDENTITY})"
codesign --force --deep --sign "${IDENTITY}" "$OUT/DJI4GManager.app"

cd "$OUT"
zip -rq "DJI4GManager-$CONFIGURATION.zip" DJI4GManager.app
shasum -a 256 "DJI4GManager-$CONFIGURATION.zip" > "DJI4GManager-$CONFIGURATION.zip.sha256"

# 只让“应用程序”里的正式副本出现在启动台，
# 取消登记 build/dist 下的临时副本，避免启动台越积越多。
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$OUT/DJI4GManager.app" >/dev/null 2>&1 || true

echo "==> Done: $OUT/DJI4GManager-$CONFIGURATION.zip"
cat "DJI4GManager-$CONFIGURATION.zip.sha256"
