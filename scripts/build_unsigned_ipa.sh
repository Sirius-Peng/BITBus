#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-"$ROOT_DIR/BITBusGrab.xcodeproj"}"
SCHEME="${SCHEME:-BITBusGrab}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-"$ROOT_DIR/.build/DerivedData"}"
OUTPUT_DIR="${OUTPUT_DIR:-"$ROOT_DIR/build"}"
APP_NAME="${APP_NAME:-}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "error: xcode project not found: $PROJECT_PATH" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$DERIVED_DATA_PATH"

echo "==> Building unsigned iOS app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  clean build

APP_PRODUCTS_DIR="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos"

if [[ -n "$APP_NAME" ]]; then
  APP_PATH="$APP_PRODUCTS_DIR/$APP_NAME.app"
else
  APP_PATH="$(find "$APP_PRODUCTS_DIR" -maxdepth 1 -type d -name '*.app' | head -n 1)"
fi

if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
  echo "error: built .app not found in $APP_PRODUCTS_DIR" >&2
  exit 1
fi

APP_BASENAME="$(basename "$APP_PATH" .app)"
IPA_PATH="$OUTPUT_DIR/${APP_BASENAME}-unsigned.ipa"
PACKAGE_DIR="$(mktemp -d)"
PAYLOAD_DIR="$PACKAGE_DIR/Payload"

mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"
rm -rf "$PAYLOAD_DIR/$APP_BASENAME.app/_CodeSignature"
rm -f "$PAYLOAD_DIR/$APP_BASENAME.app/embedded.mobileprovision"

echo "==> Packaging ipa"
(
  cd "$PACKAGE_DIR"
  /usr/bin/zip -qry "$IPA_PATH" Payload
)

rm -rf "$PACKAGE_DIR"

echo "==> Done"
echo "IPA: $IPA_PATH"
