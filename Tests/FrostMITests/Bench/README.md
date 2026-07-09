# FrostMI Test Bench

This bench keeps product data and test data sharply separated. Fixtures here are test-only inputs for parser, scanner, discovery, and future replay validation. They must never seed FrostMI product UI mock data.

## Layout

- `unit/`: small parser and scanner fixtures used by the legacy `DiscoverySelfTest` checks.
- `static/snyk/`: Snyk agent-scan-inspired static discovery fixtures. These are FrostMI-authored directory trees and config files, not copied scanner logic.
- `generated/`: deterministic FrostMI scenarios derived from local fingerprint assumptions and edge cases.
- `replay/tracelab/`: TraceLab adapter metadata and download instructions. Raw datasets are intentionally not committed.
- `runtime/`: FrostMI-authored dynamic runtime sensing fixtures adapted from TraceLab-style coding-agent traces, AgentDojo-style untrusted tool-result flows, and Atomic Red Team/osquery/Sigma-style endpoint telemetry expectations.
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

The full bench regenerates fingerprint-derived fixtures, runs discovery self-tests, runs the cold-start Agent bench in `--strict` mode, and verifies packaged app resource loading.

## Runtime Sensing Commands

Use the runtime bench when changing process attribution, runtime observation, file-event handling, Agent Analysis aggregation, or dynamic safety evidence:

```bash
Scripts/run_runtime_sensing_bench.sh
```

Current dynamic baselines:

- `runtime/tracelab/codex-tool-loop/`: validates real coding-agent loop shape inspired by TraceLab: process identity, provider evidence, LLM request, tool call, workspace context, and session memory.
- `runtime/agentdojo/untrusted-tool-result/`: validates AgentDojo-style dynamic safety signals: tool call, untrusted tool result, indirect prompt-injection evidence, and risky external destination evidence.
- `runtime/atomic-endpoint/process-file-network/`: validates endpoint telemetry shape inspired by Atomic Red Team, osquery, and Sigma: process identity, workspace file changes, outbound model endpoint evidence, and permission state.

`Scripts/run_bench_tests.sh` includes this runtime bench, so the full bench now covers both cold-start static discovery and dynamic runtime sensing.
