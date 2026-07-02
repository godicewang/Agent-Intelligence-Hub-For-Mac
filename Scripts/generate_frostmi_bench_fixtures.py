#!/usr/bin/env python3
"""Generate deterministic FrostMI discovery bench fixture skeletons.

This helper intentionally writes only test fixtures. It does not create product mock data.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FINGERPRINTS = ROOT / "Sources/FrostMI/Discovery/Fingerprints/agent_fingerprints.json"
DEFAULT_OUTPUT = ROOT / "Tests/FrostMITests/Bench/generated/fingerprint-single-agent"


def load_fingerprints() -> list[dict]:
    return json.loads(FINGERPRINTS.read_text())


def scenario_for(fingerprint: dict) -> tuple[Path, dict[str, str]]:
    name = fingerprint["normalizedName"]
    if name == "codex-cli":
        return Path("home/.codex/config.toml"), {
            "body": '[mcp_servers.generated-codex]\ncommand = "node"\nargs = ["generated-codex.js"]\n',
            "mcp": "generated-codex",
        }
    if name == "claude-code":
        return Path("home/.claude.json"), {
            "body": json.dumps({"mcpServers": {"generated-claude": {"command": "node", "args": ["generated-claude.js"]}}}, indent=2) + "\n",
            "mcp": "generated-claude",
        }
    return Path(f"project/{name}.marker"), {"body": f"{name} generated marker\n", "mcp": ""}


def write_fixture(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    fingerprints = load_fingerprints()
    expected_agents = []
    expected_mcp = []

    for fingerprint in fingerprints:
        if fingerprint["normalizedName"] not in {"claude-code", "codex-cli"}:
            continue
        rel, payload = scenario_for(fingerprint)
        target = output / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(payload["body"])
        expected_agents.append({
            "normalizedName": fingerprint["normalizedName"],
            "minCount": 1,
            "minConfidence": 50 if fingerprint["normalizedName"] == "claude-code" else 60,
        })
        if payload["mcp"]:
            expected_mcp.append({"name": payload["mcp"], "minCount": 1})

    project = output / "project"
    project.mkdir(parents=True, exist_ok=True)
    (project / "AGENTS.md").write_text("# Fingerprint Generated Fixture\n\nGenerated from FrostMI fingerprints.\n")
    manifest = {
        "schemaVersion": 1,
        "id": "generated-fingerprint-single-agent",
        "kind": "generated-discovery",
        "source": "frostmi-fingerprint-generator",
        "licenseContext": "FrostMI-authored deterministic fixture generated from local fingerprints.",
        "scan": {"home": "home", "project": "project"},
        "expected": {
            "agents": expected_agents,
            "mcpServers": expected_mcp,
            "skills": [],
            "contextFiles": [{"pathSuffix": "project/AGENTS.md"}],
            "memoryAssets": [],
            "absentMCPServers": [],
            "permissionEvidenceMinCount": 0,
        },
        "knownLimitations": ["This generated fixture is intentionally narrow; edge cases live in sibling generated scenarios."],
    }
    (output / "expected.json").write_text(json.dumps(manifest, indent=2) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    write_fixture(args.output)
    print(f"Generated {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
