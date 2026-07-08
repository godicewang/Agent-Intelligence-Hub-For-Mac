# Frost Mac Intelligence (FrostMI)

![macOS Apple Silicon](https://img.shields.io/badge/platform-macOS%20Apple%20Silicon-0A7EA4?style=flat-square)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-F05138?style=flat-square)
![Endpoint Native](https://img.shields.io/badge/architecture-endpoint--native-1F6FEB?style=flat-square)
![Local First](https://img.shields.io/badge/intelligence-local--first-159947?style=flat-square)
![Agent Sensing](https://img.shields.io/badge/current-Agent%20Sensing-0A7EA4?style=flat-square)

**Frost Mac Intelligence** (**FrostMI**, 中文名：**Frost Mac端智能**) is a macOS Apple Silicon endpoint-native intelligence platform for local AI agents, user workflows, evidence-bound memory, Prompt Copilot, and cross-agent assistance.

FrostMI 不再只是一个安全控制台。它站在 Mac 端上系统层，感知 Claude Code、Cursor、Codex CLI、Gemini CLI、Cline、Continue、OpenClaw、Aider、MCP、Skills 和企业自研 Agent 的真实行为，把可观察行为沉淀为可审计本地记忆，并用这些记忆帮助用户写出更好的 Prompt、理解跨 Agent 工作流、做出更可靠的决策。

`FrostADR` 仍然保留为 FrostMI 内部的 **Agent Runtime & ADR foundation**，用于承载发现、检测、审计、策略、审批和响应能力。用户侧产品、UI、README 和主应用命名统一使用 **FrostMI**。

## Screenshot

![FrostMI macOS Agent Sensing interface for local agent, MCP, Skill, Context, and Memory discovery](docs/images/frostmi-agent-intelligence.png)

## Quick Links / 快速跳转

- [中文界面导览](#中文界面导览)
- [English Interface Tour](#english-interface-tour)
- [Current Capabilities](#current-capabilities)
- [Launch The macOS App](#launch-the-macos-app)
- [Discovery Validation](#discovery-validation)
- [Roadmap](#roadmap)

## 中文界面导览

FrostMI 当前界面只保留 **Agent Sensing** 一个主模块。它围绕 Mac 本机 AI Agent 的端上感知展开，展示本机 Agent、MCP Server、Skills、Context、Memory 和权限状态，并支持重新构建画像、分页查看、点击定位文件路径、导出 JSONL 以及在 Finder 中打开相关资产。Codex CLI 与 Codex App 会作为不同的本机 Agent 形态分别识别，避免桌面 UI 被 CLI 指纹吞并。

| 界面区域 | 当前作用 |
| --- | --- |
| Agent Sensing | 当前已实现的真实发现模块，发现 Claude Code、Cursor、Codex CLI、Gemini CLI、MCP、Skills、Context 和 Memory。 |

其他产品方向暂不作为当前 UI 模块暴露，避免在真实能力接入前保留空占位入口。

## English Interface Tour

The current FrostMI interface exposes **Agent Sensing** as the only primary module. It is centered on endpoint-native sensing for local AI agents on macOS and discovers local Agents, MCP servers, Skills, Context files, Memory assets, and permission states. Users can rebuild the local agent profile, browse paginated inventories, click asset paths to reveal them in Finder, and export JSONL for local audit/debug workflows. Codex CLI and Codex App are detected as separate local agent surfaces so the desktop UI is not collapsed into the CLI fingerprint.

| Area | Current Role |
| --- | --- |
| Agent Sensing | Implemented real discovery module for Claude Code, Cursor, Codex CLI, Gemini CLI, MCP, Skills, Context, and Memory. |

Other product directions are intentionally not exposed as current UI modules until their real local capabilities are implemented.

## Core Positioning

- **Sensing is the foundation:** observe local AI agents, MCP configs, skills, context, memory, processes, files, and runtime candidates.
- **Memory is the center:** compile evidence-bound local memory, user profiles, project profiles, agent usage profiles, and workflow profiles.
- **Prompt Copilot is the entry point:** suggest prompt completions, rewrites, Frost Context Blocks, and risk hints without silently rewriting user intent.
- **Local assistant is the interaction layer:** answer cross-agent questions using local evidence, memory, profiles, session graphs, and audit trails.
- **Security remains the foundation:** FrostADR Runtime prevents prompt enhancement from bypassing policy, approval, privacy, or trust boundaries.

## Current Capabilities

- macOS SwiftUI app renamed and packaged as `FrostMI.app`.
- Single-module endpoint intelligence shell focused on Agent Sensing.
- Real local Agent Discovery in Agent Sensing, including separate Codex CLI / Codex App recognition and Windsurf static discovery coverage.
- Known Agent and custom Agent grouping.
- MCP server config discovery without executing MCP server commands.
- Skill discovery and lightweight pre-scan signals.
- Context and Memory metadata discovery.
- Fixed 10-row pagination across inventory and runtime status modules.
- Finder path reveal for Agent, MCP, Skill, Context, and Memory assets.
- Local JSONL export with Finder reveal.
- Default local-first, no-exec, minimum-permission discovery flow.
- Manifest-driven Agent Sensing test bench under `Tests/FrostMITests/Bench`.

## Search Keywords

`Frost Mac Intelligence`, `FrostMI`, `Mac endpoint intelligence`, `AI agent intelligence`, `AI agent security`, `Prompt Copilot`, `cross-agent memory`, `local AI memory`, `evidence-bound memory`, `agent discovery`, `agent inventory`, `MCP security`, `Model Context Protocol`, `Skill scanner`, `prompt enhancement`, `prompt injection detection`, `LLM security`, `local-first AI`, `macOS AI assistant`, `SwiftUI macOS app`, `FrostADR Runtime`, `Agent Detection and Response`.

## Recommended GitHub Topics

For repository discovery, add these topics in GitHub's **About** sidebar:

`frostmi`, `mac-intelligence`, `ai-agent-intelligence`, `prompt-copilot`, `local-ai-memory`, `cross-agent-assistant`, `endpoint-intelligence`, `ai-agent-security`, `agent-discovery`, `mcp-security`, `model-context-protocol`, `llm-security`, `macos-security`, `swiftui`, `apple-silicon`, `local-first`, `agent-inventory`, `skill-scanner`, `jsonl`, `frostadr-runtime`.

Suggested repository description:

> Frost Mac Intelligence (FrostMI): local-first macOS endpoint intelligence for AI agents, Agent Sensing, MCP/Skill discovery, evidence-bound memory, Prompt Copilot, and FrostADR Runtime.

See [GitHub SEO Checklist](docs/github-seo.md) for About sidebar, social preview, release title, and keyword maintenance notes.

## Architecture Direction

FrostMI is designed as an endpoint-first product:

- **UI:** macOS SwiftUI app plus future NSPanel Prompt Copilot.
- **Sensing:** known path fingerprints, config schema parsing, workspace scanning, process fingerprints, FSEvents, and runtime observation.
- **FrostADR Runtime:** local discovery, policy, detection, approval, audit, and response foundation.
- **Knowledge Store:** SQLite, FTS5, and future embedded vector retrieval for local memory and profile compilation.
- **Prompt Intelligence:** suggestion-first prompt enhancement with auditable Frost Context Blocks.
- **Model Router:** replaceable provider interface for local models, OpenAI-compatible providers, DeepSeek, and future Apple Foundation Models.
- **Export:** JSONL for debug, audit, and portability.

## Discovery Validation

Run the discovery self-test and bundled app resource check:

```bash
Scripts/run_discovery_tests.sh
```

The script runs Agent Discovery self-tests, builds `dist/FrostMI.app`, verifies bundled fingerprint resources, and runs self-tests through the packaged app. Current checks cover MCP config detection and false-positive control, Codex plugin MCP discovery, known agent fingerprints, targeted home/support-directory discovery, workspace scanning, Skill script signals, discovery source markers, cold-start snapshot replacement, JSONL export integrity, path resolver behavior, minimum-permission boundaries, and manifest-driven bench fixtures.

For a focused cold-start Agent discovery bench:

```bash
Scripts/run_cold_start_agent_bench.sh
```

This regenerates fingerprint-derived fixtures, runs the same full cold-start scanner path used by Agent Sensing, and prints per-fixture counts for agents, MCP servers, skills, context files, memory assets, and permission evidence. It uses `Tests/FrostMITests/Bench/static/snyk` and `Tests/FrostMITests/Bench/generated` because those datasets are purpose-built for static endpoint discovery.

For stricter quality review:

```bash
Scripts/run_cold_start_agent_bench.sh --audit
Scripts/run_cold_start_agent_bench.sh --strict
```

`--audit` keeps the normal minimum expected-label check, then lists extra assets, duplicate candidates, missing owner links, and owner mismatches without failing the command. `--strict` treats those audit findings as failures.

For the current full bench path:

```bash
Scripts/run_bench_tests.sh
```

The bench lives under `Tests/FrostMITests/Bench` and includes Snyk-inspired static discovery fixtures, FrostMI-generated edge cases, external dataset adapter manifests, a compact Claude trace graph sample, and a SHA256-pinned TraceLab downloader. The full bench runs cold-start discovery in strict mode so extra assets, duplicate candidates, and owner mismatches fail the validation. Large external datasets are kept under git-ignored `datasets/`.

To fetch the fixed TraceLab v0.0.1 JSONL dataset for future replay work:

```bash
Scripts/fetch_tracelab_dataset.sh
```

For local discovery debugging, run:

```bash
swift run FrostMI --discovery-print-summary
```

## Launch The macOS App

For the easiest local preview, double-click `FrostMI.command` in Finder. It builds a debug app bundle at `dist/FrostMI.app` and opens it.

From Terminal, run:

```bash
./FrostMI.command
```

To build a release app bundle for local use, double-click `PackageFrostMI.command` or run:

```bash
./PackageFrostMI.command
```

The reusable build script is:

```bash
Scripts/build_app.sh --debug --open
Scripts/build_app.sh --release
```

Generated build output lives under `dist/` and is intentionally not committed.

## Roadmap

The following capabilities are product directions and are not exposed as current UI modules yet:

- Prompt Copilot floating panel with global shortcut, focused-app detection, selected text extraction, copy / insert / accept / reject, and feedback logging.
- Evidence-bound Memory System with typed memories, origin trust, allowed use, disallowed use, and poisoning risk.
- Profile Compiler for user, project, agent, workflow, and security profiles.
- Cross-Agent Assistant grounded in local SQL, FTS, vector retrieval, and session graph traversal.
- Model Router with local and external providers behind a privacy-preserving interface.
- Session Graph reconstruction from observable prompts, tools, commands, files, network, and memory writes.
- FrostADR Runtime policy, approval, rewrite, block, audit, and response workflows.

## Status

FrostMI is an early-stage macOS endpoint intelligence project. The current app intentionally exposes only the real Agent Sensing / Discovery foundation. Prompt Copilot, Memory/Profile, Assistant, Model Router, full Endpoint Security integration, Network Extension enforcement, MCP wrapping, and Local LLM Proxy features remain product directions, but they are not presented as active UI modules yet.

If this direction is useful to you, please Star the repository so more Mac AI, agent intelligence, and endpoint security builders can find it.
