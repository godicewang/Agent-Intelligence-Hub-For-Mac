#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$ROOT_DIR/datasets/tracelab"
TARGET_FILE="$TARGET_DIR/syfi_coding_trace.jsonl.gz"
URL="https://github.com/uw-syfi/TraceLab/releases/download/v0.0.1/syfi_coding_trace.jsonl.gz"
SHA256="9d265eae69a31cae203848bea936f018148eed7ca8bf56050c5abe96da0b4e6b"

mkdir -p "$TARGET_DIR"
curl -L --fail -o "$TARGET_FILE" "$URL"

if command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$TARGET_FILE" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$TARGET_FILE" | awk '{print $1}')"
else
  echo "No SHA256 tool found." >&2
  exit 1
fi

if [[ "$actual" != "$SHA256" ]]; then
  echo "TraceLab SHA256 mismatch: expected $SHA256, got $actual" >&2
  exit 1
fi

gzip -t "$TARGET_FILE"
echo "Downloaded and verified $TARGET_FILE"
