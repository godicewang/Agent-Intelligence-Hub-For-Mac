#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 Scripts/generate_frostmi_bench_fixtures.py
swift run FrostMI --discovery-self-test
swift run FrostMI --cold-start-agent-bench --strict
Scripts/run_runtime_sensing_bench.sh
Scripts/run_discovery_tests.sh
