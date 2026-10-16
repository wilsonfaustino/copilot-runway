import Foundation

public struct SessionCredits: Sendable {
  public let byModel: [ModelCredits]
  public let byCategory: [CategoryCredits]
  public let bySource: [SourceCredits]
  public let byDay: [DailyCredits]
  public let warning: String?

  // Every aggregate comes from the same turns, so all dashboard totals add up.
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
    let piTurns = PiSessionParser.turns(inDirectory: piDirectory, since: cycleStart)
    var turns = piTurns.turns
    if piTurns.hasUndecodableFile {
      warnings.append("Cannot read some Pi sessions.")
    }
    do {
      turns += try OpenCodeSessionParser.turns(inDirectory: openCodeDirectory, since: cycleStart)
    } catch {
      warnings.append("Cannot read OpenCode sessions.")
    }
    let records = turns.flatMap(\.records)
    return SessionCredits(
      byModel: Credits.byModel(records: records, prices: prices),
      byCategory: Credits.byCategory(turns: turns, prices: prices),
      bySource: Credits.bySource(turns: turns, prices: prices),
      byDay: Credits.byDay(records: records, prices: prices, cycleStart: cycleStart, now: now, calendar: Runway.utcCalendar),
      warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
    )
  }
}
