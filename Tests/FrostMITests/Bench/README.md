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
