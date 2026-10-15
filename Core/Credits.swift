import Foundation

public struct ModelCredits: Equatable, Sendable {
  public let model: String
  // nil when the price table has no entry for the model.
  public let credits: Double?

  public init(model: String, credits: Double?) {
    self.model = model
    self.credits = credits
  }
}

public enum Credits {
  // 1 AI credit = $0.01 USD (GitHub models and pricing page).
  static let usdPerCredit = 0.01
  static let tokensPerPriceUnit = 1_000_000.0

  public static func credits(for tokens: TokenUsage, price: ModelPrice) -> Double {
    let rates = price.rates(promptTokens: tokens.promptTokens)
    let usd = (
      Double(tokens.input) * rates.input
        + Double(tokens.cachedInput) * rates.cachedInput
        + Double(tokens.cacheWrite) * rates.cacheWrite
        + Double(tokens.output) * rates.output
    ) / tokensPerPriceUnit
    return usd / usdPerCredit
  }

  // Credits are summed per message, because the long context tier depends on each request's size.
  // Highest spend first, models without a price last.
  public static func byModel(records: [UsageRecord], prices: [String: ModelPrice]) -> [ModelCredits] {
    let recordsByModel = Dictionary(grouping: records, by: \.model)
    let modelCredits = recordsByModel.map { model, modelRecords in
      ModelCredits(
        model: model,
        credits: prices[model].map { price in modelRecords.reduce(0) { $0 + credits(for: $1.tokens, price: price) } }
      )
    }
    return modelCredits.sorted { left, right in
      if left.credits != right.credits { return (left.credits ?? -1) > (right.credits ?? -1) }
      return left.model < right.model
    }
  }
}
