#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="debug"
OPEN_APP=false
CLEAN=false

usage() {
  cat <<'USAGE'
Usage: Scripts/build_app.sh [--debug|--release] [--open] [--clean]

Builds the SwiftPM FrostADR executable and wraps it as a macOS app bundle:
  dist/FrostADR.app

Options:
  --debug     Build a debug app bundle. This is the default.
  --release   Build a release app bundle for local distribution.
  --open      Open the generated app after packaging.
  --clean     Remove the previous dist/FrostADR.app before building.
  --help      Show this help text.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      CONFIGURATION="debug"
      ;;
    --release)
      CONFIGURATION="release"
      ;;
    --open)
      OPEN_APP=true
      ;;
    --clean)
      CLEAN=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

APP_NAME="FrostADR"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

if [[ "$CLEAN" == true ]]; then
  rm -rf "$APP_DIR"
fi

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BIN_DIR/$APP_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Expected executable was not produced: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/Packaging/FrostADR-Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_DIR/"
fi
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

echo "Built $APP_DIR"

if [[ "$OPEN_APP" == true ]]; then
  open "$APP_DIR"
fi
