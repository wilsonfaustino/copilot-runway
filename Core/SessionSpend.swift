import Foundation

// The credits of one session in this cycle, from Credits.bySession. No title or message text: the label is built
// from the record times, agent, top model and biggest task.
public struct SessionSpend: Equatable, Sendable, Identifiable {
  // The dashboard Top sessions card lists this many sessions.
  public static let topCount = 5

  // The session id, or the root session id when OpenCode subagent sessions are folded in.
  public let id: String
  public let project: String
  public let source: SessionSource
  public let turnCount: Int
  public let credits: Double
  public let firstRecord: Date
  public let lastRecord: Date
  // The model with the most credits, ties by id. When no model has a price, the first id.
  public let topModel: String
  // The task with the most credits, ties as in Credits.byCategory.
  public let biggestTask: TaskCategory
  public let biggestTaskCredits: Double

  public init(
    id: String,
    project: String,
    source: SessionSource,
    turnCount: Int,
    credits: Double,
    firstRecord: Date,
    lastRecord: Date,
    topModel: String,
    biggestTask: TaskCategory,
    biggestTaskCredits: Double
  ) {
    self.id = id
    self.project = project
    self.source = source
    self.turnCount = turnCount
    self.credits = credits
    self.firstRecord = firstRecord
    self.lastRecord = lastRecord
    self.topModel = topModel
    self.biggestTask = biggestTask
    self.biggestTaskCredits = biggestTaskCredits
  }

  // "Oct 7 · Pi · Gemini 3.8 Flash · Debugging". Days are UTC days, as on the dashboard.
  public func label(locale: Locale = .current) -> String {
    [dayRange(locale: locale), source.displayName, ModelDisplayName.name(for: topModel), biggestTask.displayName]
      .joined(separator: " · ")
  }

  // "Oct 7", "Oct 14 to 15" in one month, "Oct 31 to Nov 1" across months.
  func dayRange(locale: Locale) -> String {
    let calendar = Runway.utcCalendar
    let monthDayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
    let firstDay = firstRecord.formatted(monthDayStyle)
    if calendar.isDate(firstRecord, inSameDayAs: lastRecord) { return firstDay }
    let lastDayStyle = calendar.isDate(firstRecord, equalTo: lastRecord, toGranularity: .month)
      ? Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day()
      : monthDayStyle
    return "\(firstDay) to \(lastRecord.formatted(lastDayStyle))"
  }

  // The share of total with one decimal, for example "11.9%".
  public func sharePercentText(of total: Double, locale: Locale = .current) -> String {
    let share = total > 0 ? credits / total * 100 : 0
    return share.formatted(.number.precision(.fractionLength(1)).locale(locale)) + "%"
  }

  // The rounded percent of total in the top topCount sessions. sessions are highest spend first.
  public static func topShare(_ sessions: [SessionSpend], of total: Double) -> Int {
    Credits.sharePercent(sessions.prefix(topCount).reduce(0) { $0 + $1.credits }, of: total)
  }

  // "The top session cost 1,489 credits in 9 turns, 41% of it debugging." nil without sessions.
  public static func topSentence(_ sessions: [SessionSpend], locale: Locale = .current) -> String? {
    guard let topSession = sessions.first else { return nil }
    let turns = topSession.turnCount == 1 ? "1 turn" : "\(topSession.turnCount) turns"
    let taskPercent = Credits.sharePercent(topSession.biggestTaskCredits, of: topSession.credits)
    return "The top session cost \(Credits.formatted(topSession.credits, locale: locale)) credits in \(turns),"
      + " \(taskPercent)% of it \(topSession.biggestTask.rawValue)."
  }
}
