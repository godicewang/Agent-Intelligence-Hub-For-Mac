# FrostMI Test Bench

This bench keeps product data and test data sharply separated. Fixtures here are test-only inputs for parser, scanner, discovery, and future replay validation. They must never seed FrostMI product UI mock data.

## Layout

- `unit/`: small parser and scanner fixtures used by the legacy `DiscoverySelfTest` checks.
- `static/snyk/`: Snyk agent-scan-inspired static discovery fixtures. These are FrostMI-authored directory trees and config files, not copied scanner logic.
- `generated/`: deterministic FrostMI scenarios derived from local fingerprint assumptions and edge cases.
- `replay/tracelab/`: TraceLab adapter metadata and download instructions. Raw datasets are intentionally not committed.
- `golden/claude-native-traces/`: compact Claude Code trace samples and expected graph manifests.
- `tool-trajectories/traject-bench/`: TRAJECT-Bench adapter area for tool ordering and dependency tests.
- `security/agentdojo/`: AgentDojo adapter area for prompt-injection and safe tool-flow tests.
- `pressure/swe-agent/`: SWE-agent adapter area for stress and failure-trajectory tests.

Every committed executable fixture should include an `expected.json` manifest.

## Agent Discovery Commands

Use the focused cold-start bench when changing Agent Sensing or static discovery behavior:

```bash
Scripts/run_cold_start_agent_bench.sh
```

It runs full cold-start discovery against `static/snyk/` and `generated/`, then reports fixture-level counts for agents, MCP servers, skills, context files, memory assets, and permission evidence.

Additional modes:

```bash
Scripts/run_cold_start_agent_bench.sh --audit
Scripts/run_cold_start_agent_bench.sh --strict
```

- `--audit` reports extra assets, duplicate candidates, missing owner links, and owner mismatches while preserving the normal coverage pass/fail result.
- `--strict` promotes those audit findings to failures so regressions cannot hide behind minimum expected-label coverage.

Use the full bench path when changing shared parser, scanner, packaging, fixture, or bench infrastructure:

```bash
Scripts/run_bench_tests.sh
```

The full bench regenerates fingerprint-derived fixtures, runs discovery self-tests, runs the cold-start Agent bench, and verifies packaged app resource loading.
