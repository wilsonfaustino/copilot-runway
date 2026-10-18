import Foundation

public struct SessionCredits: Sendable {
  public let byModel: [ModelCredits]
  public let byCategory: [CategoryCredits]
  public let byModelAndCategory: [ModelCategoryCredits]
  public let bySource: [SourceCredits]
  public let byDay: [DailyCredits]
  // The last cycle, one entry per UTC day from its start through the day before this cycle starts.
  public let previousByDay: [DailyCredits]
  // Same order as byModel.
  public let cacheHits: [ModelCacheHit]
  // One sentence per model with a low cache hit rate, for the dashboard note.
  public let lowCacheSentences: [String]
  // Cost per edit turn and retry rate for the dashboard By model note. nil when no model qualifies.
  public let modelEfficiencyNote: String?
  // byDay against the same days of previousByDay, for the Daily burn chart. nil without enough last cycle data.
  public let cycleComparisonSentence: String?
  public let warning: String?

  public static func load(
    since cycleStart: Date,
    now: Date,
    piDirectory: URL = PiSessionParser.sessionsDirectory,
    openCodeDirectory: URL = OpenCodeSessionParser.dataDirectory,
    priceURL: URL = PriceTable.overrideURL
  ) -> SessionCredits {
    var warnings: [String] = []
    let prices: [String: ModelPrice]
    do {
      prices = try PriceTable.load(overrideURL: priceURL)
    } catch {
      prices = PriceTable.bundled
      warnings.append("prices.json is invalid. Using bundled prices.")
    }
    // One cycle back, for previousByDay. aggregate keeps the earlier records out of every current total.
    let previousCycleStart = Runway.cycleStart(resetDate: cycleStart)
    let piTurns = PiSessionParser.turns(inDirectory: piDirectory, since: previousCycleStart)
    var turns = piTurns.turns
    if piTurns.hasUndecodableFile {
      warnings.append("Cannot read some Pi sessions.")
    }
    do {
      turns += try OpenCodeSessionParser.turns(inDirectory: openCodeDirectory, since: previousCycleStart, splitAt: cycleStart)
    } catch {
      warnings.append("Cannot read OpenCode sessions.")
    }
    return aggregate(
      turns: turns,
      prices: prices,
      cycleStart: cycleStart,
      now: now,
      warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
    )
  }

  // Every aggregate comes from the same turns, so all dashboard totals add up. turns can start in the last cycle:
  // records before cycleStart go only to previousByDay, and a turn with no record left in this cycle drops out.
  static func aggregate(
    turns: [Turn],
    prices: [String: ModelPrice],
    cycleStart: Date,
    now: Date,
    warning: String? = nil,
    locale: Locale = .current
  ) -> SessionCredits {
    let currentTurns = turns.compactMap { turn -> Turn? in
      var currentTurn = turn
      currentTurn.records = turn.records.filter { $0.timestamp >= cycleStart }
      return currentTurn.records.isEmpty ? nil : currentTurn
    }
    let records = currentTurns.flatMap(\.records)
    let previousRecords = turns.flatMap(\.records).filter { $0.timestamp < cycleStart }
    let cacheHits = CacheHit.byModel(records: records, prices: prices)
    let byDay = Credits.byDay(records: records, prices: prices, cycleStart: cycleStart, now: now, calendar: Runway.utcCalendar)
    let previousByDay = Credits.byDay(
      records: previousRecords,
      prices: prices,
      cycleStart: Runway.cycleStart(resetDate: cycleStart),
      now: cycleStart.addingTimeInterval(-1),
      calendar: Runway.utcCalendar
    )
    return SessionCredits(
      byModel: Credits.byModel(records: records, prices: prices),
      byCategory: Credits.byCategory(turns: currentTurns, prices: prices),
      byModelAndCategory: Credits.byModelAndCategory(turns: currentTurns, prices: prices),
      bySource: Credits.bySource(turns: currentTurns, prices: prices),
      byDay: byDay,
      previousByDay: previousByDay,
      cacheHits: cacheHits,
      lowCacheSentences: CacheHit.lowSentences(cacheHits: cacheHits, prices: prices),
      modelEfficiencyNote: ModelEfficiency.note(ModelEfficiency.byModel(turns: currentTurns, prices: prices)),
      cycleComparisonSentence: CycleComparison.compare(current: byDay, previous: previousByDay)?.sentence(locale: locale),
      warning: warning
    )
  }
}
