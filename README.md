# FrostADR

FrostADR 是一款面向 macOS Apple Silicon 的端上 Agent Detection & Response（Agent-EDR）产品。它聚焦本机 AI Agent 的发现、画像、审计与风险线索收集，优先在本地完成轻量扫描与数据导出，为后续 MCP、Skill、上下文、Memory、策略与运行时防护能力预留扩展空间。

当前版本以 **Agent Scan** 为核心，提供本机 Agent 画像构建、常见 Agent 与自研 Agent 分组、MCP / Skill / Context / Memory 发现，以及 JSONL 本地导出等基础能力。

## 项目截图

![FrostADR Agent Scan](docs/images/frostadr-agent-scan.png)

## 当前重点

- macOS SwiftUI 原生端上安全界面
- 本机 Agent、MCP、Skill、上下文与 Memory 轻量发现
- 常见 Agent 与本机自研 Agent 分组展示
- 本地 JSONL 导出与 Finder 定位
- 默认本地优先、no-exec、最小权限的发现流程

## 启动 macOS App

For the easiest local preview, double-click `FrostADR.command` in Finder.
It builds a debug app bundle at `dist/FrostADR.app` and opens it.

From Terminal, run:

```bash
./FrostADR.command
```

To build a release app bundle for local use, double-click `PackageFrostADR.command` or run:

```bash
./PackageFrostADR.command
```

The reusable build script is:

```bash
Scripts/build_app.sh --debug --open
Scripts/build_app.sh --release
```

Generated build output lives under `dist/` and is intentionally not committed.
