import Foundation

struct BehaviorFingerprintInput: Hashable {
  var processName: String
  var executablePath: String?
  var argv: [String]
  var cwd: String?
  var parentChain: [String]
  var connectedLLMProviders: [String]
  var spawnedCommandCount: Int
  var workspaceTouched: String?
  var hasWorkspaceAgentContext: Bool
  var hasMCPOrToolSchema: Bool
  var wroteSessionLikeFile: Bool
  var observedLLMCommandLoop: Bool
}

struct BehaviorFingerprintResult: Hashable {
  var state: BehaviorState
  var score: Int
  var evidenceSummaries: [String]
}

enum BehaviorState: String, Codable, CaseIterable, Hashable {
  case unknownProcess
  case llmCaller
  case toolExecutor
  case workspaceMutator
  case feedbackLoopObserved
  case agentCandidate
  case confirmedAgent
}

final class BehaviorFingerprintEngine {
  func evaluate(_ input: BehaviorFingerprintInput) -> BehaviorFingerprintResult {
    var score = 0
    var evidence: [String] = []
    let argv = input.argv.joined(separator: " ").lowercased()
    let parentChain = input.parentChain.joined(separator: " ").lowercased()

    if !input.connectedLLMProviders.isEmpty {
      score += 25
      evidence.append("Connected to known LLM provider")
    }
    if argv.contains("/v1/chat/completions") || argv.contains("/v1/responses")
      || argv.contains("/messages")
    {
      score += 20
      evidence.append("Arguments reference LLM API routes")
    }
    if argv.range(
      of: #"OPENAI_API_KEY|ANTHROPIC_API_KEY|DEEPSEEK_API_KEY|GEMINI_API_KEY"#,
      options: [.regularExpression, .caseInsensitive]) != nil
    {
      score += 20
      evidence.append("Arguments reference LLM API key names")
    }
    if ["bash", "python", "node", "git", "npm", "curl"].contains(where: {
      argv.contains($0) || parentChain.contains($0)
    }) {
      score += 15
      evidence.append("Process or ancestry references common tool execution commands")
    }
    if input.workspaceTouched != nil {
      score += 10
      evidence.append("Workspace path associated with process")
    }
    if input.wroteSessionLikeFile {
      score += 15
      evidence.append("Session or memory-like file observed")
    }
    if input.hasWorkspaceAgentContext {
      score += 15
      evidence.append("Workspace contains agent context marker")
    }
    if input.hasMCPOrToolSchema {
      score += 20
      evidence.append("MCP/tool schema marker associated with process")
    }
    if input.observedLLMCommandLoop {
      score += 50
      evidence.append("LLM request and command execution feedback loop observed")
    }

    let clamped = score.clampedConfidence
    return BehaviorFingerprintResult(
      state: state(for: clamped, input: input), score: clamped, evidenceSummaries: evidence)
  }

  private func state(for score: Int, input: BehaviorFingerprintInput) -> BehaviorState {
    if score >= 80 { return .confirmedAgent }
    if score >= 60 { return .agentCandidate }
    if input.observedLLMCommandLoop { return .feedbackLoopObserved }
    if input.workspaceTouched != nil { return .workspaceMutator }
    if input.spawnedCommandCount > 0 { return .toolExecutor }
    if !input.connectedLLMProviders.isEmpty { return .llmCaller }
    return .unknownProcess
  }
}
