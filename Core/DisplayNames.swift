import Foundation

extension SessionSource {
  public var displayName: String {
    switch self {
    case .pi: "Pi"
    case .opencode: "OpenCode"
    case .omp: "omp"
    }
  }
}

extension TaskCategory {
  public var displayName: String { rawValue.capitalized }
}

// Names are as GitHub writes them on https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing.
// Keys are the ids in PriceTable.bundled.
public enum ModelDisplayName {
  public static let bundled: [String: String] = [
    "gpt-5-mini": "GPT-5 mini",
    "gpt-5.3-codex": "GPT-5.3-Codex",
    "gpt-5.4": "GPT-5.4",
    "gpt-5.4-mini": "GPT-5.4 mini",
    "gpt-5.4-nano": "GPT-5.4 nano",
    "gpt-5.5": "GPT-5.5",
    "gpt-5.6-luna": "GPT-5.6 Luna",
    "gpt-5.6-sol": "GPT-5.6 Sol",
    "gpt-5.6-terra": "GPT-5.6 Terra",
    "gpt-6-astra": "GPT-6 Astra",
    "gpt-6-luna": "GPT-6 Luna",
    "gpt-6-sol": "GPT-6 Sol",
    "gpt-6.1-sol": "GPT-6.1 Sol",
    "claude-haiku-4.5": "Claude Haiku 4.5",
    "claude-haiku-5.5": "Claude Haiku 5.5",
    "claude-sonnet-4": "Claude Sonnet 4",
    "claude-sonnet-4.6": "Claude Sonnet 4.6",
    "claude-opus-4.8": "Claude Opus 4.8",
    "claude-opus-5": "Claude Opus 5",
    "claude-opus-5.5": "Claude Opus 5.5",
    "claude-sonnet-5": "Claude Sonnet 5",
    "claude-sonnet-5.5": "Claude Sonnet 5.5",
    "claude-fable-5": "Claude Fable 5",
    "claude-fable-5.1": "Claude Fable 5.1",
    "gemini-3.7-flash": "Gemini 3.7 Flash",
    "gemini-3.8-flash": "Gemini 3.8 Flash",
    "gemini-4-argon": "Gemini 4 Argon",
    "mai-code-1.1-flash": "MAI-Code-1.1-Flash",
    "grok-4.5": "Grok 4.5",
    "grok-4.6": "Grok 4.6",
    "grok-4.7": "Grok 4.7",
    "kimi-k3": "Kimi K3",
  ]

  // An id with no name shows as itself.
  public static func name(for modelID: String) -> String {
    bundled[modelID] ?? modelID
  }
}
