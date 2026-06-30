#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift run FrostADR --discovery-self-test
Scripts/build_app.sh --debug --clean
test -f "$ROOT_DIR/dist/FrostADR.app/FrostADR_FrostADR.bundle/agent_fingerprints.json"
"$ROOT_DIR/dist/FrostADR.app/Contents/MacOS/FrostADR" --discovery-self-test
