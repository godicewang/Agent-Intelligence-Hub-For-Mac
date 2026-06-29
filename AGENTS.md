Project Mission

Build an endpoint-native Agent Detection & Response product for macOS Apple Silicon. The product runs primarily on the endpoint and provides local discovery, telemetry, static scanning, decision-chain reconstruction, detection, rewrite/block, approval, and audit for AI agents such as Claude Code, Cursor, Codex CLI, OpenClaw, Cline, Continue, Gemini CLI, and enterprise custom agents.

The server side is only a control plane for policy distribution, detector/rule versioning, log aggregation, audit search, alerting, and fleet management. Runtime inspection and enforcement must happen on the endpoint.

Core Product Shape

Implement two deployable components:

control-plane
Web console, policy management, rule packs, detector configuration, endpoint inventory, audit search, alerting.
No inline enforcement on the server.
endpoint-edr
macOS Apple Silicon system-level app.
Includes UI, daemon, local policy engine, scanner, local proxy/wrapper, telemetry collector, and enforcement modules.
UI style should resemble enterprise EDR / zero-trust security products: clean dark/light dashboard, endpoint status, risk timeline, agent inventory, alerts, policy hits, session graph, and local approval prompts.
Implementation Principles

Prefer mature open-source references or adaptation before building from scratch. If an open-source project is incompatible with the product architecture, license, macOS deployment model, or endpoint-first design, implement a minimal clean version ourselves.

Code must be simple, modular, testable, and production-oriented. Avoid over-engineering. Prefer small interfaces, typed event schemas, deterministic rules, and clear separation between collectors, scanners, detectors, policy, storage, and UI.

Never vendor GPL or unclear-license code without explicit approval. It is acceptable to study GPL projects as references, but avoid copying code.

macOS System Architecture

Target macOS on Apple Silicon first.

Use macOS-native mechanisms:

Endpoint Security Framework for process/file/auth telemetry and enforcement where entitlement allows.
Network Extension / content filter / local proxy for network visibility and blocking.
LaunchDaemon or SMAppService-style helper for privileged background service.
XPC for communication between GUI app, daemon, system extension, and helper.
SwiftUI for the macOS app UI.
SQLite for local endpoint storage unless there is a strong reason not to.
JSONL export for debug/audit portability.

If required entitlements are unavailable during development, implement a degraded mode:

static scanning,
cache parsing,
local proxy,
MCP wrapper,
passive process/network observation,
mock Endpoint Security events for tests.
Major Modules
1. Agent Discovery

Automatically discover local agents and related assets. Do not require users to manually configure paths unless auto-discovery fails.

Discover:

Claude Code / Claude Desktop
Cursor
Codex CLI
Gemini CLI
Cline / RooCode / Continue
OpenClaw
Aider and unknown custom agents
MCP configs
skills
memory/cache/session files
context files such as AGENTS.md, CLAUDE.md, .cursor/rules, mcp.json, settings.json

Implement discovery by:

known path fingerprints,
process fingerprints,
config schema detection,
workspace scanning,
behavior heuristics,
incremental filesystem watch.

Output normalized AgentAsset records with confidence, source, path, owner, workspace, risk, and managed status.

2. Data Collection and Decision Reconstruction

Collect endpoint events from four sources:

Agent cache/session parsers
Parse JSONL, SQLite, logs, project cache, conversation history.
Extract user prompt, model request, model response, tool call, tool result, workspace, file changes, session id, and timestamps where available.
Local LLM proxy
Prefer base_url or provider config rewrite over TLS MITM.
Capture OpenAI/Anthropic-compatible messages, tools, function calls, streaming responses, model names, latency, and token metadata.
Default to privacy-preserving mode: redact secrets locally before storing or uploading.
MCP/tool wrapper
For stdio MCP, wrap the command and proxy stdin/stdout.
For HTTP/SSE MCP, use a local proxy.
Capture tools/list, tool schemas, tool descriptions, tools/call, arguments, results, errors, and latency.
OS/system sensor
Capture process tree, exec, command argv, cwd, file reads/writes/deletes, network connects, DNS if available, and sensitive file access.
Attribute system events back to agent sessions using process tree, time window, workspace, command similarity, and file/path correlation.

Build a local session graph:
UserPrompt -> LLMRequest -> LLMResponse -> ToolDiscovery -> ToolCall -> ToolResult -> CommandExec -> FileRead/FileWrite -> NetworkConnect -> MemoryWrite -> FinalResponse.

Do not claim to reconstruct hidden model chain-of-thought. Reconstruct only observable decision and execution chains.

3. Static Scanning

Static scanning is a first-class product feature.

Scan MCP, skills, tools, context files, and memory files before runtime trust is granted.

MCP scanner:

Parse MCP configs and server commands.
Extract tools/list when safe.
Scan tool names, descriptions, schemas, prompts, resources, command args, env, package metadata, and source files.
Detect prompt injection, tool poisoning, tool shadowing, rug pull, toxic flow, excessive permission, suspicious command, schema over-breadth, and auth/scope risk.
Pin manifest hashes and alert on later changes.

Skill scanner:

Scan SKILL.md, frontmatter, description, scripts, templates, resources, setup instructions, dependencies, binaries, URLs, and permissions.
Detect hidden instructions, social engineering, credential theft, external exfiltration, permission mismatch, obfuscation, cross-file inconsistency, and malicious install behavior.
Use a three-stage triage:
fast regex / metadata / AST / secret / URL / dependency checks,
optional semantic LLM decomposition,
optional high-risk multi-review or admin approval.

Memory scanner:

Treat memory as untrusted unless origin-bound.
Scan long-term memory, vector store metadata, summaries, procedural memory, tool-selection history, and conversation summaries.
Detect persistent instructions, tool hijacking hints, approval bypass, trigger phrases, external destinations, and untrusted-origin laundering.
Every memory item must carry origin, trust, writer, session, source hash, allowed use, and disallowed use.
4. Detection

Use layered detection. Do not rely on a single LLM classifier.

Layers:

deterministic lifecycle rules,
secret/DLP scanners,
prompt-injection and jailbreak classifiers,
tool-call alignment checks,
source-sink and toxic-flow analysis,
behavioral sequence rules,
session risk scoring,
optional heavy reasoning detector for high-risk uncertain cases.

Rules should operate on normalized events and phases:
agent_discovery, llm_request, llm_response, tool_discovery, tool_call_pre, tool_result_post, command_pre, file_event, network_event, memory_write, final_response.

Actions:
observe, score, allow, block, rewrite, redact, sanitize, confirm, sandbox, quarantine, rate_limit, alert.

5. Rewrite and Blocking

Prefer graceful blocking before system-level blocking.

Priority:

Local MCP/tool wrapper: hide tools, block calls, rewrite args, sanitize results.
Local LLM proxy: redact prompts, block unsafe function calls, rewrite responses.
Tool execution broker: block command before execution, require approval, sandbox high-risk execution.
macOS Endpoint/Network enforcement: deny/kill/block as fallback.

Do not depend only on OS-level blocking. OS-level enforcement is a safety net, not the main UX.

6. Tool Execution Broker and Sandbox

High-risk commands must route through a local broker when possible.

Broker responsibilities:

parse command,
normalize args,
enforce workspace/path policy,
restrict network,
scan secrets,
require approval for risky commands,
execute in sandbox when needed,
scan stdout/stderr/artifacts before returning to the agent.

Sandbox may be local restricted process/container-like isolation where feasible. For macOS MVP, implement a minimal restricted execution strategy first, then abstract the runner for stronger backends later.

7. UI Requirements

Build a professional macOS endpoint security UI.

Required views:

Endpoint status
Agent inventory
MCP/Skill inventory
Risk dashboard
Alert timeline
Session graph
Policy/rule hits
Static scan findings
Local approval dialog
Settings and privacy controls

Design language:

enterprise security product,
clean spacing,
high information density,
dark/light mode,
severity badges,
trace graph,
audit-first interactions.
8. Privacy and Safety

Default to local-first processing.
Redact secrets before persistence and upload.
Do not upload raw prompts, files, tool outputs, or memory content unless policy explicitly allows.
Always preserve a local audit trail for enforcement actions.
Never log API keys, private keys, tokens, cookies, or full secret values.

9. Testing

Every feature must include tests where practical.

Required test types:

unit tests for parsers, scanners, rules, and event normalization,
fixture-based tests for MCP configs, skills, memory files, and agent cache samples,
integration tests for MCP stdio wrapper and local proxy,
UI snapshot or view-model tests where feasible,
mock Endpoint Security events for system sensor logic.

Do not merge code that cannot be built or tested locally unless the limitation is documented.

10. Code Management

At the start of each task:

inspect git status,
do not overwrite unrelated user changes,
understand the current architecture before editing.

At the end of each task:

format code,
run relevant tests/builds,
update docs or fixtures if behavior changed,
run git status,
commit all task-related changes automatically.

Commit rules:

use concise conventional messages, e.g. feat(endpoint): add MCP config discovery;
do not commit secrets, local certificates, build artifacts, or large generated files;
one task should normally produce one focused commit;
if tests cannot run, include the reason in the commit message body or final response.
11. Preferred Open-Source References

Study and adapt ideas from:

Santa for macOS binary/file authorization architecture.
osquery for endpoint inventory and query-style visibility.
LuLu for macOS network blocking UX.
Snyk agent-scan for agent/MCP/skill inventory and scan categories.
mcp-scan for MCP prompt injection, tool poisoning, and rug-pull scanning.
SkillSieve-style triage for malicious skill detection.
LiteLLM / Invariant Gateway / mitmproxy for local LLM proxy ideas.
OPA/Rego-style policy concepts if useful, but keep the first rule engine simple.

Prefer integration or compatible reuse only when it reduces complexity and license risk. Otherwise implement a minimal focused module.

12. Out of Scope for MVP

Do not prioritize:

Linux eBPF implementation,
Windows driver/ETW implementation,
full cloud SIEM replacement,
full TLS MITM by default,
complete hidden chain-of-thought reconstruction,
heavyweight Kubernetes deployment,
multi-tenant server enforcement.

Focus on macOS endpoint-native Agent-EDR first.
