import Foundation

public struct TokenUsage: Equatable, Sendable {
  public let input: Int
  public let cachedInput: Int
  public let cacheWrite: Int
  // Includes reasoning tokens, which bill at the output rate.
  public let output: Int

  public init(input: Int, cachedInput: Int, cacheWrite: Int, output: Int) {
    self.input = input
    self.cachedInput = cachedInput
    self.cacheWrite = cacheWrite
    self.output = output
  }

  public var promptTokens: Int { input + cachedInput + cacheWrite }
}

// One assistant message billed through GitHub Copilot.
public struct UsageRecord: Equatable, Sendable {
  public let model: String
  public let timestamp: Date
  public let tokens: TokenUsage

  public init(model: String, timestamp: Date, tokens: TokenUsage) {
    self.model = model
    self.timestamp = timestamp
    self.tokens = tokens
  }
}
