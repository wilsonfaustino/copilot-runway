import Foundation

// This cycle's local credits against the same days of the last cycle. Days pair by their index from each cycle
// start, and both sides are totals so far, so one busy day does not decide the result.
public struct CycleComparison: Equatable, Sendable {
  // The last full day of this cycle in the comparison, that is yesterday.
  public let throughDay: Date
  // Rounded. Above 0 means more credits than the last cycle.
  public let percentDifference: Int

  public init(throughDay: Date, percentDifference: Int) {
    self.throughDay = throughDay
    self.percentDifference = percentDifference
  }
}

extension CycleComparison {
  // Under about 5 active days, one busy day decides the comparison. Missing old sessions also look like quiet days.
  static let minimumActivePreviousDays = 5

  // current and previous come from Credits.byDay, so index 0 is each cycle's first day.
  // The last current entry is today, which is not over yet, so the comparison stops at yesterday.
  // Past the last cycle's final day, the whole last cycle is the comparison.
  public static func compare(current: [DailyCredits], previous: [DailyCredits]) -> CycleComparison? {
    guard current.count >= 2 else { return nil }
    let yesterdayIndex = current.count - 2
    let pairedPrevious = previous.prefix(yesterdayIndex + 1)
    let activePreviousDays = pairedPrevious.filter { $0.credits > 0 }.count
    let previousTotal = pairedPrevious.reduce(0) { $0 + $1.credits }
    guard activePreviousDays >= minimumActivePreviousDays, previousTotal > 0 else { return nil }
    let currentTotal = current.prefix(yesterdayIndex + 1).reduce(0) { $0 + $1.credits }
    return CycleComparison(
      throughDay: current[yesterdayIndex].day,
      percentDifference: Int(((currentTotal - previousTotal) / previousTotal * 100).rounded())
    )
  }

  public func sentence(locale: Locale = .current) -> String {
    let start = "Local credits through \(RunwayInsight.day(throughDay, locale: locale)) are"
    if percentDifference == 0 { return "\(start) about the same as last cycle." }
    let direction = percentDifference > 0 ? "above" : "below"
    return "\(start) \(abs(percentDifference))% \(direction) the same days of last cycle."
  }
}
