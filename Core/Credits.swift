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

public struct ProjectCredits: Equatable, Sendable {
  public let name: String
  public let credits: Double

  public init(name: String, credits: Double) {
    self.name = name
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

  // Grouped by project name, so the same repo under two folders counts once. Same pricing rule as byCategory.
  // Highest spend first.
  public static func byProject(turns: [Turn], prices: [String: ModelPrice], projectName: (Turn) -> String) -> [ProjectCredits] {
    let turnsByProject = Dictionary(grouping: turns, by: projectName)
    let projectCredits = turnsByProject.map { name, projectTurns in
      ProjectCredits(name: name, credits: pricedTotal(records: projectTurns.flatMap(\.records), prices: prices))
    }
    return projectCredits.sorted { left, right in
      if left.credits != right.credits { return left.credits > right.credits }
      return left.name < right.name
    }
  }

  // One entry per session, with OpenCode subagent sessions folded into their root session. Turns without a session
  // id form one entry per source. Only OpenCode has parents, so Pi and omp ids never fold through an OpenCode edge.
  // openCodeParents holds parent ids of sessions without a turn in turns. Same pricing rule as byCategory.
  // Highest spend first.
  public static func bySession(
    turns: [Turn], prices: [String: ModelPrice], openCodeParents: [String: String] = [:], projectName: (Turn) -> String
  ) -> [SessionSpend] {
    let turnParents = Dictionary(
      turns.compactMap { turn -> (String, String)? in
        guard turn.source == .opencode, let sessionId = turn.sessionId, let parentId = turn.parentSessionId else { return nil }
        return (sessionId, parentId)
      },
      uniquingKeysWith: min
    )
    let parentBySession = turnParents.merging(openCodeParents) { _, openCodeParent in openCodeParent }
    let turnsBySession = Dictionary(grouping: turns) { turn in
      let sessionId = turn.sessionId ?? ""
      let rootId = turn.source == .opencode ? rootSessionId(of: sessionId, parentBySession: parentBySession) : sessionId
      return SessionKey(source: turn.source, id: rootId)
    }
    let sessionSpends = turnsBySession.compactMap { key, sessionTurns -> SessionSpend? in
      let records = sessionTurns.flatMap(\.records)
      guard let firstRecord = records.map(\.timestamp).min(), let lastRecord = records.map(\.timestamp).max(),
        let topModel = byModel(records: records, prices: prices).first,
        let biggestTask = byCategory(turns: sessionTurns, prices: prices).first
      else { return nil }
      // The root session's own folder names the project. A root with no turn left in the cycle takes the first
      // child by id, so the name does not depend on the order of turns.
      let projectTurn = sessionTurns.first { $0.sessionId == key.id }
        ?? sessionTurns.min { ($0.sessionId ?? "", $0.timestamp) < ($1.sessionId ?? "", $1.timestamp) }!
      return SessionSpend(
        id: key.id,
        project: projectName(projectTurn),
        source: key.source,
        turnCount: sessionTurns.count,
        credits: pricedTotal(records: records, prices: prices),
        firstRecord: firstRecord,
        lastRecord: lastRecord,
        topModel: topModel.model,
        biggestTask: biggestTask.category,
        biggestTaskCredits: biggestTask.credits
      )
    }
    return sessionSpends.sorted { left, right in
      if left.credits != right.credits { return left.credits > right.credits }
      if left.firstRecord != right.firstRecord { return left.firstRecord < right.firstRecord }
      return left.id < right.id
    }
  }

  private struct SessionKey: Hashable {
    let source: SessionSource
    let id: String
  }

  // Subagents can start their own subagents, so the walk goes up to the first session without a known parent.
  // The parent ids of a cycle have no top, so every session that reaches the cycle takes its smallest id as root.
  private static func rootSessionId(of sessionId: String, parentBySession: [String: String]) -> String {
    var path = [sessionId]
    while let parentId = parentBySession[path[path.count - 1]] {
      if let cycleStart = path.firstIndex(of: parentId) {
        return path[cycleStart...].min() ?? parentId
      }
      path.append(parentId)
    }
    return path[path.count - 1]
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

  // Whole percents of parts, in order, with the largest remainder method: each part gets its rounded-down share,
  // then the parts with the largest remainders get 1 more each, the first part on a tie. They add up to the
  // rounded percent that the parts are of total, which is 100 when the parts fill the total.
  public static func sharePercents(_ parts: [Double], of total: Double) -> [Int] {
    guard total > 0 else { return parts.map { _ in 0 } }
    let exactPercents = parts.map { max($0, 0) / total * 100 }
    var percents = exactPercents.map { Int($0.rounded(.down)) }
    let extraPercents = Int(exactPercents.reduce(0, +).rounded()) - percents.reduce(0, +)
    // Rounded to 6 places so float noise does not break a tie such as 1/6, 1/6 and 2/3.
    let remainders = exactPercents.indices.map { ((exactPercents[$0] - Double(percents[$0])) * 1e6).rounded() }
    let indicesByRemainder = exactPercents.indices.sorted { left, right in
      remainders[left] != remainders[right] ? remainders[left] > remainders[right] : left < right
    }
    for index in indicesByRemainder.prefix(max(extraPercents, 0)) {
      percents[index] += 1
    }
    return percents
  }

  // The share text of a part with this whole percent. A part with credits that has 0% shows "<1%".
  public static func shareLabel(percent: Int, of part: Double) -> String {
    percent == 0 && part > 0 ? "<1%" : "\(percent)%"
  }

  static func pricedTotal(records: [UsageRecord], prices: [String: ModelPrice]) -> Double {
    records.reduce(0) { total, record in
      total + (prices[record.model].map { credits(for: record.tokens, price: $0) } ?? 0)
    }
  }
}
