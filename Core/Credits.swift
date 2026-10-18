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

public struct CategoryCredits: Equatable, Sendable {
  public let category: TaskCategory
  public let credits: Double

  public init(category: TaskCategory, credits: Double) {
    self.category = category
    self.credits = credits
  }
}

public struct ModelCategoryCredits: Equatable, Sendable {
  public let model: String
  public let category: TaskCategory
  public let credits: Double

  public init(model: String, category: TaskCategory, credits: Double) {
    self.model = model
    self.category = category
    self.credits = credits
  }
}

public struct SourceCredits: Equatable, Sendable {
  public let source: SessionSource
  public let credits: Double

  public init(source: SessionSource, credits: Double) {
    self.source = source
    self.credits = credits
  }
}

public struct DailyCredits: Equatable, Sendable {
  // Start of the day in the calendar given to Credits.byDay.
  public let day: Date
  public let credits: Double

  public init(day: Date, credits: Double) {
    self.day = day
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

  private static func summedCredits(of records: [UsageRecord], price: ModelPrice) -> Double {
    records.reduce(0) { $0 + credits(for: $1.tokens, price: price) }
  }

  // Credits are summed per message, because the long context tier depends on each request's size.
  // Highest spend first, models without a price last.
  public static func byModel(records: [UsageRecord], prices: [String: ModelPrice]) -> [ModelCredits] {
    let recordsByModel = Dictionary(grouping: records, by: \.model)
    let modelCredits = recordsByModel.map { model, modelRecords in
      ModelCredits(
        model: model,
        credits: prices[model].map { price in summedCredits(of: modelRecords, price: price) }
      )
    }
    return modelCredits.sorted { left, right in
      if left.credits != right.credits { return (left.credits ?? -1) > (right.credits ?? -1) }
      return left.model < right.model
    }
  }

  // Each turn gets one category. Messages from models without a price add 0, so the total equals
  // the sum of the priced models in byModel. Highest spend first.
  public static func byCategory(turns: [Turn], prices: [String: ModelPrice]) -> [CategoryCredits] {
    let turnsByCategory = Dictionary(grouping: turns, by: TaskCategorizer.category(of:))
    let categoryCredits = turnsByCategory.map { category, categoryTurns in
      CategoryCredits(
        category: category,
        credits: pricedTotal(records: categoryTurns.flatMap(\.records), prices: prices)
      )
    }
    return categoryCredits.sorted { left, right in
      if left.credits != right.credits { return left.credits > right.credits }
      return left.category.rawValue < right.category.rawValue
    }
  }

  // A turn can mix models, so each message goes to its own model and the category of its turn. Models without
  // a price are left out, so the totals per model equal byModel and the totals per category equal byCategory.
  // Highest spend first.
  public static func byModelAndCategory(turns: [Turn], prices: [String: ModelPrice]) -> [ModelCategoryCredits] {
    var creditsByKey: [ModelCategoryKey: Double] = [:]
    for turn in turns {
      let category = TaskCategorizer.category(of: turn)
      for record in turn.records {
        guard let price = prices[record.model] else { continue }
        creditsByKey[ModelCategoryKey(model: record.model, category: category), default: 0] += credits(for: record.tokens, price: price)
      }
    }
    let modelCategoryCredits = creditsByKey.map { key, credits in
      ModelCategoryCredits(model: key.model, category: key.category, credits: credits)
    }
    return modelCategoryCredits.sorted { left, right in
      if left.credits != right.credits { return left.credits > right.credits }
      if left.model != right.model { return left.model < right.model }
      return left.category.rawValue < right.category.rawValue
    }
  }

  private struct ModelCategoryKey: Hashable {
    let model: String
    let category: TaskCategory
  }

  // Same pricing rule as byCategory: messages from models without a price add 0. Highest spend first.
  public static func bySource(turns: [Turn], prices: [String: ModelPrice]) -> [SourceCredits] {
    let turnsBySource = Dictionary(grouping: turns, by: \.source)
    let sourceCredits = turnsBySource.map { source, sourceTurns in
      SourceCredits(source: source, credits: pricedTotal(records: sourceTurns.flatMap(\.records), prices: prices))
    }
    return sourceCredits.sorted { left, right in
      if left.credits != right.credits { return left.credits > right.credits }
      return left.source.rawValue < right.source.rawValue
    }
  }

  // One entry per calendar day from the cycle start through now, days without messages at 0.
  // The app passes Runway.utcCalendar, so the days line up with the UTC cycle boundaries.
  public static func byDay(
    records: [UsageRecord],
    prices: [String: ModelPrice],
    cycleStart: Date,
    now: Date,
    calendar: Calendar
  ) -> [DailyCredits] {
    let recordsByDay = Dictionary(grouping: records) { calendar.startOfDay(for: $0.timestamp) }
    var dailyCredits: [DailyCredits] = []
    var day = calendar.startOfDay(for: cycleStart)
    while day <= now {
      dailyCredits.append(DailyCredits(day: day, credits: pricedTotal(records: recordsByDay[day] ?? [], prices: prices)))
      day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return dailyCredits
  }

  // Whole credits for display, for example "1,234" in en_US.
  public static func formatted(_ credits: Double, locale: Locale = .current) -> String {
    credits.formatted(.number.precision(.fractionLength(0)).locale(locale))
  }

  // The rounded percent that part is of total. 0 when total is 0 or less.
  public static func sharePercent(_ part: Double, of total: Double) -> Int {
    guard total > 0 else { return 0 }
    return Int((part / total * 100).rounded())
  }

  // The By task share text. A share above 0 that rounds to 0% shows "<1%".
  public static func shareLabel(_ part: Double, of total: Double) -> String {
    let percent = sharePercent(part, of: total)
    return percent == 0 && part > 0 && total > 0 ? "<1%" : "\(percent)%"
  }

  static func pricedTotal(records: [UsageRecord], prices: [String: ModelPrice]) -> Double {
    records.reduce(0) { total, record in
      total + (prices[record.model].map { credits(for: record.tokens, price: $0) } ?? 0)
    }
  }
}
