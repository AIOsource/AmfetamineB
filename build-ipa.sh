#!/bin/bash
set -euo pipefail

CONFIG="${1:-Release}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==> Building AmfetamineB ($CONFIG)..."
rm -rf build/DerivedData build/Payload build/*.app build/*.ipa
mkdir -p build

if command -v xcodegen &> /dev/null; then
    echo "==> Generating Xcode project via xcodegen..."
    xcodegen generate
fi

PROJ_NAME="AmfetamineB"

xcodebuild -project "${PROJ_NAME}.xcodeproj" \
    -scheme "${PROJ_NAME}" \
    -configuration "$CONFIG" \
    -derivedDataPath build/DerivedData \
    -destination 'generic/platform=iOS' \
    clean build \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED="NO"

APP_PATH="$(find build/DerivedData/Build/Products -name "*.app" -type d | head -n 1)"
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Error: App bundle not found in DerivedData"
    exit 1
fi

echo "==> Packaging IPA..."
cp -R "$APP_PATH" build/AmfetamineB.app

# Clean any existing signature
rm -rf build/AmfetamineB.app/_CodeSignature
rm -rf build/AmfetamineB.app/embedded.mobileprovision

mkdir -p build/Payload
cp -R build/AmfetamineB.app build/Payload/AmfetamineB.app

cd build
zip -qr "AmfetamineB.ipa" Payload
rm -rf Payload AmfetamineB.app

echo "==> Done! IPA generated at: $ROOT/build/AmfetamineB.ipa"
ls -lh "$ROOT/build/AmfetamineB.ipa"
