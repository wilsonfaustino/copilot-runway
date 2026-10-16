import Foundation

public struct ModelCacheHit: Equatable, Sendable {
  public let model: String
  // cachedInput / promptTokens. nil when the model has no prompt tokens.
  public let rate: Double?

  public init(model: String, rate: Double?) {
    self.model = model
    self.rate = rate
  }

  public var isLow: Bool { rate.map { $0 < CacheHit.lowThreshold } ?? false }

  public var wholePercent: Int? {
    guard let rate else { return nil }
    let percent = Int((rate * 100).rounded())
    // A low rate such as 0.499 rounds to 50%, which reads as not low.
    return isLow ? min(percent, Int(CacheHit.lowThreshold * 100) - 1) : percent
  }
}

public enum CacheHit {
  public static let lowThreshold = 0.5
  // Tolerance for the price ratio match, because 0.075 / 0.75 is not exactly 0.1 as a Double.
  static let ratioTolerance = 1e-9
  static let ratioWords: [(ratio: Double, words: String)] = [
    (1.0 / 20, "one twentieth"),
    (1.0 / 10, "one tenth"),
    (1.0 / 4, "one quarter"),
    (1.0 / 2, "half"),
  ]

  public static func rate(records: [UsageRecord]) -> Double? {
    let promptTokens = records.reduce(0) { $0 + $1.tokens.promptTokens }
    guard promptTokens > 0 else { return nil }
    let cachedInput = records.reduce(0) { $0 + $1.tokens.cachedInput }
    return Double(cachedInput) / Double(promptTokens)
  }

  // Same order as Credits.byModel: highest credits first, models without a price last.
  public static func byModel(records: [UsageRecord], prices: [String: ModelPrice]) -> [ModelCacheHit] {
    let recordsByModel = Dictionary(grouping: records, by: \.model)
    return Credits.byModel(records: records, prices: prices).map { modelCredits in
      ModelCacheHit(model: modelCredits.model, rate: rate(records: recordsByModel[modelCredits.model] ?? []))
    }
  }

  // One sentence per low model, in the order of cacheHits.
  public static func lowSentences(cacheHits: [ModelCacheHit], prices: [String: ModelPrice]) -> [String] {
    cacheHits.filter(\.isLow).compactMap { cacheHit in
      cacheHit.wholePercent.map { sentence(model: cacheHit.model, percent: $0, price: prices[cacheHit.model]) }
    }
  }

  static func sentence(model: String, percent: Int, price: ModelPrice?) -> String {
    let rateSentence = "\(model) cache hit is \(percent)%."
    guard let price, price.standard.input > 0, price.standard.cachedInput > 0 else { return rateSentence }
    let priceRatio = price.standard.cachedInput / price.standard.input
    let priceWords = ratioWords.first { abs($0.ratio - priceRatio) < ratioTolerance }?.words
      ?? "\(Int((priceRatio * 100).rounded()))% of the price"
    return "\(rateSentence) Cached input costs \(priceWords) of fresh input."
  }
}
