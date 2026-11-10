import Foundation

// One assistant message sent through Portkey. Never a UsageRecord, never part of a turn, never priced with PriceTable.
public struct PortkeyRecord: Equatable, Sendable {
  public let model: String
  public let timestamp: Date
  public let source: SessionSource
  // The cost the agent stored, in USD. nil when the message has none: the record is unpriced.
  public let costUSD: Double?

  public init(model: String, timestamp: Date, source: SessionSource, costUSD: Double?) {
    self.model = model
    self.timestamp = timestamp
    self.source = source
    self.costUSD = costUSD
  }

  // Provider ids seen: "portkey" (Pi, omp) and "portkey-openai-compatible" (OpenCode). Users can rename them.
  static func isPortkey(provider: String) -> Bool {
    provider.range(of: "portkey", options: .caseInsensitive) != nil
  }
}

public struct PortkeyModelSpend: Equatable, Sendable {
  public let model: String
  public let usd: Double
  public let requestCount: Int
}

public struct PortkeySourceSpend: Equatable, Sendable {
  public let source: SessionSource
  public let usd: Double
  public let requestCount: Int
}

public struct PortkeyModelSourceSpend: Equatable, Sendable {
  public let model: String
  public let source: SessionSource
  public let usd: Double
  public let requestCount: Int
}

// The Portkey records of one cycle. Amounts are USD, apart from Copilot credits. Unpriced records count as
// requests and add 0 USD.
public struct PortkeySpend: Equatable, Sendable {
  public let records: [PortkeyRecord]

  public init(records: [PortkeyRecord]) {
    self.records = records
  }

  public var totalUSD: Double { Self.usd(of: records) }
  public var requestCount: Int { records.count }
  public var unpricedCount: Int { records.filter { $0.costUSD == nil }.count }

  // Over the priced requests only. nil when no request has a cost.
  public var averageUSDPerRequest: Double? {
    let pricedCount = requestCount - unpricedCount
    return pricedCount > 0 ? totalUSD / Double(pricedCount) : nil
  }

  // Highest spend first, then by id.
  public var byModel: [PortkeyModelSpend] {
    Dictionary(grouping: records, by: \.model)
      .map { PortkeyModelSpend(model: $0.key, usd: Self.usd(of: $0.value), requestCount: $0.value.count) }
      .sorted { ($1.usd, $0.model) < ($0.usd, $1.model) }
  }

  // Highest spend first, then by source.
  public var bySource: [PortkeySourceSpend] {
    Dictionary(grouping: records, by: \.source)
      .map { PortkeySourceSpend(source: $0.key, usd: Self.usd(of: $0.value), requestCount: $0.value.count) }
      .sorted { ($1.usd, $0.source.rawValue) < ($0.usd, $1.source.rawValue) }
  }

  // Cells of the model by agent table: models in byModel order, then highest spend first within a model.
  public var byModelAndSource: [PortkeyModelSourceSpend] {
    let modelRank = Dictionary(uniqueKeysWithValues: byModel.enumerated().map { ($0.element.model, $0.offset) })
    return Dictionary(grouping: records) { ModelSourceKey(model: $0.model, source: $0.source) }
      .map { PortkeyModelSourceSpend(model: $0.key.model, source: $0.key.source, usd: Self.usd(of: $0.value), requestCount: $0.value.count) }
      .sorted {
        (modelRank[$0.model]!, $1.usd, $0.source.rawValue) < (modelRank[$1.model]!, $0.usd, $1.source.rawValue)
      }
  }

  // For example "DeepSeek V4.1 Flash is 99% of Portkey spend, about $0.004 per request." nil with no spend.
  public func insightSentence(locale: Locale = .current) -> String? {
    guard totalUSD > 0, let topModel = byModel.first, let averageUSDPerRequest else { return nil }
    let share = Credits.sharePercent(topModel.usd, of: totalUSD)
    return "\(ModelDisplayName.name(for: topModel.model)) is \(share)% of Portkey spend, "
      + "about \(Self.formatted(averageUSDPerRequest, locale: locale)) per request."
  }

  // Cents, for example "$0.73". An amount that rounds below 1 cent keeps a third decimal, for example "$0.004".
  public static func formatted(_ usd: Double, locale: Locale = .current) -> String {
    let fractionLength = usd == 0 || abs(usd) >= 0.0095 ? 2 : 3
    return usd.formatted(.currency(code: "USD").precision(.fractionLength(fractionLength)).locale(locale))
  }

  private static func usd(of records: [PortkeyRecord]) -> Double {
    records.reduce(0) { $0 + ($1.costUSD ?? 0) }
  }

  private struct ModelSourceKey: Hashable {
    let model: String
    let source: SessionSource
  }
}
