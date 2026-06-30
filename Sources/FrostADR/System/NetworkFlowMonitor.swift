import Foundation
import NetworkExtension
import Security

final class NetworkFlowMonitor {
  func permissionState() -> DiscoveryPermissionState {
    let entitlement = "com.apple.developer.networking.networkextension" as CFString
    let task = SecTaskCreateFromSelf(nil)
    let value = task.flatMap { SecTaskCopyValueForEntitlement($0, entitlement, nil) }
    let hasEntitlement =
      (value as? Bool) == true || ((value as? [String])?.isEmpty == false)
    return DiscoveryPermissionState(
      id: UUID(),
      capability: .networkExtension,
      status: hasEntitlement ? .available : .missingEntitlement,
      message: hasEntitlement
        ? "Network Extension entitlement is present; flow monitor can attach when configured."
        : "Network Extension entitlement is missing in this development build.",
      checkedAt: Date()
    )
  }

  func knownProviderName(for host: String) -> String? {
    let lower = host.lowercased()
    if lower.contains("api.openai.com") { return "OpenAI" }
    if lower.contains("anthropic.com") { return "Anthropic" }
    if lower.contains("generativelanguage.googleapis.com") { return "Gemini" }
    if lower.contains("deepseek.com") { return "DeepSeek" }
    if lower.contains("ollama") || lower.contains("localhost") { return "Ollama" }
    if lower.contains("litellm") { return "LiteLLM" }
    return nil
  }
}
