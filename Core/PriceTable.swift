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
  public static let bundled: [String: ModelPrice] = [
    "gpt-6.1-sol": ModelPrice(
      standard: TokenRates(input: 2.00, cachedInput: 0.10, cacheWrite: 2.50, output: 10.00),
      longContextThreshold: 272_000,
      longContext: TokenRates(input: 4.00, cachedInput: 0.20, cacheWrite: 5.00, output: 15.00)
    ),
    "gpt-6-luna": ModelPrice(
      standard: TokenRates(input: 0.10, cachedInput: 0.01, cacheWrite: 0.125, output: 0.50),
      longContextThreshold: 272_000,
      longContext: TokenRates(input: 0.20, cachedInput: 0.02, cacheWrite: 0.25, output: 0.75)
    ),
    // Promotional rate through December 31, 2026. GitHub lists no cache write rate for Google models.
    "gemini-3.8-flash": ModelPrice(
      standard: TokenRates(input: 0.75, cachedInput: 0.075, cacheWrite: 0, output: 3.75)
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
