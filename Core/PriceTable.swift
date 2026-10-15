import Foundation

// USD per 1 million tokens.
public struct TokenRates: Codable, Equatable, Sendable {
  public let input: Double
  public let cachedInput: Double
  public let cacheWrite: Double
  public let output: Double

  public init(input: Double, cachedInput: Double, cacheWrite: Double, output: Double) {
    self.input = input
    self.cachedInput = cachedInput
    self.cacheWrite = cacheWrite
    self.output = output
  }
}

public struct ModelPrice: Codable, Equatable, Sendable {
  public let standard: TokenRates
  public let longContextThreshold: Int?
  public let longContext: TokenRates?

  public init(standard: TokenRates, longContextThreshold: Int? = nil, longContext: TokenRates? = nil) {
    self.standard = standard
    self.longContextThreshold = longContextThreshold
    self.longContext = longContext
  }

  // Long context rates apply to the whole request when its prompt tokens exceed the threshold.
  public func rates(promptTokens: Int) -> TokenRates {
    if let longContextThreshold, let longContext, promptTokens > longContextThreshold { return longContext }
    return standard
  }
}

public enum PriceTableError: Error, Equatable, Sendable {
  case invalidOverride
}

public enum PriceTable {
  public static let overrideURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".config/copilot-runway/prices.json")

  // Source: https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing
  // Model ids are the lowercase GitHub model names with hyphens, as OpenCode and Pi write them.
  // The long context threshold is the page value, with 1K as 1,000 tokens.
  public static let bundled: [String: ModelPrice] = [
    // OpenAI. GitHub lists cache write as not applicable for models before GPT-5.6, so it is 0 for them.
    "gpt-5-mini": ModelPrice(
      standard: TokenRates(input: 0.25, cachedInput: 0.025, cacheWrite: 0, output: 2.00)
    ),
    "gpt-5.3-codex": ModelPrice(
      standard: TokenRates(input: 1.75, cachedInput: 0.175, cacheWrite: 0, output: 14.00)
    ),
    "gpt-5.4": ModelPrice(
      standard: TokenRates(input: 2.50, cachedInput: 0.25, cacheWrite: 0, output: 15.00),
      longContextThreshold: 272_000,
      longContext: TokenRates(input: 5.00, cachedInput: 0.50, cacheWrite: 0, output: 22.50)
    ),
    "gpt-5.4-mini": ModelPrice(
      standard: TokenRates(input: 0.75, cachedInput: 0.075, cacheWrite: 0, output: 4.50)
    ),
    "gpt-5.4-nano": ModelPrice(
      standard: TokenRates(input: 0.20, cachedInput: 0.02, cacheWrite: 0, output: 1.25)
    ),
    "gpt-5.5": ModelPrice(
      standard: TokenRates(input: 5.00, cachedInput: 0.50, cacheWrite: 0, output: 30.00),
      longContextThreshold: 272_000,
      longContext: TokenRates(input: 10.00, cachedInput: 1.00, cacheWrite: 0, output: 45.00)
    ),
    "gpt-5.6-luna": ModelPrice(
      standard: TokenRates(input: 0.20, cachedInput: 0.02, cacheWrite: 0.25, output: 1.20),
      longContextThreshold: 200_000,
      longContext: TokenRates(input: 0.40, cachedInput: 0.04, cacheWrite: 0.50, output: 1.80)
    ),
    "gpt-5.6-sol": ModelPrice(
      standard: TokenRates(input: 4.00, cachedInput: 0.40, cacheWrite: 5.00, output: 20.00),
      longContextThreshold: 272_000,
      longContext: TokenRates(input: 8.00, cachedInput: 0.80, cacheWrite: 10.00, output: 30.00)
    ),
    "gpt-5.6-terra": ModelPrice(
      standard: TokenRates(input: 2.00, cachedInput: 0.20, cacheWrite: 2.50, output: 12.00),
      longContextThreshold: 272_000,
      longContext: TokenRates(input: 4.00, cachedInput: 0.40, cacheWrite: 5.00, output: 18.00)
    ),
    "gpt-6-astra": ModelPrice(
      standard: TokenRates(input: 10.00, cachedInput: 1.00, cacheWrite: 12.50, output: 50.00),
      longContextThreshold: 272_000,
      longContext: TokenRates(input: 20.00, cachedInput: 2.00, cacheWrite: 25.00, output: 75.00)
    ),
    "gpt-6-luna": ModelPrice(
      standard: TokenRates(input: 0.10, cachedInput: 0.01, cacheWrite: 0.125, output: 0.50),
      longContextThreshold: 272_000,
      longContext: TokenRates(input: 0.20, cachedInput: 0.02, cacheWrite: 0.25, output: 0.75)
    ),
    "gpt-6-sol": ModelPrice(
      standard: TokenRates(input: 2.00, cachedInput: 0.20, cacheWrite: 2.50, output: 10.00),
      longContextThreshold: 272_000,
      longContext: TokenRates(input: 4.00, cachedInput: 0.40, cacheWrite: 5.00, output: 15.00)
    ),
    "gpt-6.1-sol": ModelPrice(
      standard: TokenRates(input: 2.00, cachedInput: 0.10, cacheWrite: 2.50, output: 10.00),
      longContextThreshold: 272_000,
      longContext: TokenRates(input: 4.00, cachedInput: 0.20, cacheWrite: 5.00, output: 15.00)
    ),
    // Anthropic. All models list a cache write rate. Claude Opus 4.8 (fast mode) is not listed here because its model id is not known.
    "claude-haiku-4.5": ModelPrice(
      standard: TokenRates(input: 1.00, cachedInput: 0.10, cacheWrite: 1.25, output: 5.00)
    ),
    "claude-haiku-5.5": ModelPrice(
      standard: TokenRates(input: 0.10, cachedInput: 0.01, cacheWrite: 0.125, output: 0.50),
      longContextThreshold: 100_000,
      longContext: TokenRates(input: 0.50, cachedInput: 0.05, cacheWrite: 0.625, output: 2.50)
    ),
    "claude-sonnet-4": ModelPrice(
      standard: TokenRates(input: 3.00, cachedInput: 0.30, cacheWrite: 3.75, output: 15.00)
    ),
    "claude-sonnet-4.6": ModelPrice(
      standard: TokenRates(input: 3.00, cachedInput: 0.30, cacheWrite: 3.75, output: 15.00)
    ),
    "claude-opus-4.8": ModelPrice(
      standard: TokenRates(input: 5.00, cachedInput: 0.50, cacheWrite: 6.25, output: 25.00)
    ),
    "claude-opus-5": ModelPrice(
      standard: TokenRates(input: 5.00, cachedInput: 0.50, cacheWrite: 6.25, output: 25.00)
    ),
    "claude-opus-5.5": ModelPrice(
      standard: TokenRates(input: 4.00, cachedInput: 0.20, cacheWrite: 5.00, output: 20.00)
    ),
    "claude-sonnet-5": ModelPrice(
      standard: TokenRates(input: 2.00, cachedInput: 0.20, cacheWrite: 2.50, output: 10.00)
    ),
    "claude-sonnet-5.5": ModelPrice(
      standard: TokenRates(input: 2.00, cachedInput: 0.10, cacheWrite: 2.50, output: 10.00)
    ),
    "claude-fable-5": ModelPrice(
      standard: TokenRates(input: 10.00, cachedInput: 1.00, cacheWrite: 12.50, output: 50.00)
    ),
    "claude-fable-5.1": ModelPrice(
      standard: TokenRates(input: 10.00, cachedInput: 0.25, cacheWrite: 12.50, output: 50.00)
    ),
    // Google. GitHub lists no cache write rate for Google models, so it is 0.
    // Promotional rate through December 31, 2026.
    "gemini-3.7-flash": ModelPrice(
      standard: TokenRates(input: 0.75, cachedInput: 0.075, cacheWrite: 0, output: 3.75)
    ),
    // Promotional rate through December 31, 2026.
    "gemini-3.8-flash": ModelPrice(
      standard: TokenRates(input: 0.75, cachedInput: 0.075, cacheWrite: 0, output: 3.75)
    ),
    // Promotional rate until December 1, 2026.
    "gemini-4-argon": ModelPrice(
      standard: TokenRates(input: 2.00, cachedInput: 0.10, cacheWrite: 0, output: 10.00)
    ),
    // Microsoft. GitHub lists no cache write rate, so it is 0.
    "mai-code-1.1-flash": ModelPrice(
      standard: TokenRates(input: 0.20, cachedInput: 0.02, cacheWrite: 0, output: 1.20)
    ),
    // xAI. GitHub lists no cache write rate, so it is 0.
    "grok-4.5": ModelPrice(
      standard: TokenRates(input: 2.00, cachedInput: 0.50, cacheWrite: 0, output: 6.00),
      longContextThreshold: 200_000,
      longContext: TokenRates(input: 4.00, cachedInput: 1.00, cacheWrite: 0, output: 12.00)
    ),
    "grok-4.6": ModelPrice(
      standard: TokenRates(input: 2.00, cachedInput: 0.50, cacheWrite: 0, output: 6.00),
      longContextThreshold: 200_000,
      longContext: TokenRates(input: 4.00, cachedInput: 1.00, cacheWrite: 0, output: 12.00)
    ),
    "grok-4.7": ModelPrice(
      standard: TokenRates(input: 2.00, cachedInput: 0.50, cacheWrite: 0, output: 6.00),
      longContextThreshold: 200_000,
      longContext: TokenRates(input: 4.00, cachedInput: 1.00, cacheWrite: 0, output: 12.00)
    ),
    // Moonshot AI. GitHub lists no cache write rate, so it is 0.
    "kimi-k3": ModelPrice(
      standard: TokenRates(input: 3.00, cachedInput: 0.30, cacheWrite: 0, output: 15.00)
    ),
  ]

  // Entries in the override replace bundled entries with the same model id.
  public static func load(overrideURL: URL = overrideURL) throws -> [String: ModelPrice] {
    guard FileManager.default.fileExists(atPath: overrideURL.path) else { return bundled }
    guard
      let overrideData = try? Data(contentsOf: overrideURL),
      let overridePrices = try? JSONDecoder().decode([String: ModelPrice].self, from: overrideData)
    else { throw PriceTableError.invalidOverride }
    return bundled.merging(overridePrices) { _, overridePrice in overridePrice }
  }
}
