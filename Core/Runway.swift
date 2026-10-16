import Foundation

public enum Runway {
  static let secondsPerDay: Double = 86_400

  // The billing cycle starts and resets at midnight UTC.
  public static let utcCalendar: Calendar = {
    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = TimeZone(identifier: "UTC")!
    return utcCalendar
  }()

  public static func cycleStart(resetDate: Date) -> Date {
    utcCalendar.date(byAdding: .month, value: -1, to: resetDate)!
  }

  // The reset date is the first day of the next cycle, so the cycle ends the day before.
  public static func lastCycleDay(resetDate: Date) -> Date {
    utcCalendar.date(byAdding: .day, value: -1, to: resetDate)!
  }

  // Elapsed time counts as at least one day, so the first hours of a cycle do not inflate the burn.
  public static func averageDailyBurn(credits: Double, resetDate: Date, now: Date) -> Double {
    let elapsedDays = now.timeIntervalSince(cycleStart(resetDate: resetDate)) / secondsPerDay
    return credits / max(elapsedDays, 1)
  }

  public static func averageDailyBurn(usage: CopilotUsage, now: Date) -> Double {
    averageDailyBurn(credits: usage.creditsUsed, resetDate: usage.resetDate, now: now)
  }

  // daysLeft = remaining / averageDailyBurn over the current billing cycle.
  public static func daysLeft(usage: CopilotUsage, now: Date) -> Double? {
    guard !usage.isUnlimited, usage.creditsUsed > 0 else { return nil }
    return usage.creditsRemaining / averageDailyBurn(usage: usage, now: now)
  }

  // Floored and never below 0, so overage shows 0 days. The menu bar, popover and dashboard all use it.
  public static func wholeDaysLeft(usage: CopilotUsage, now: Date) -> Int? {
    daysLeft(usage: usage, now: now).map { max(Int($0.rounded(.down)), 0) }
  }

  // Rounded and never below 0, so overage shows 0%. The menu bar, popover and dashboard all use it.
  public static func wholePercentRemaining(usage: CopilotUsage) -> Int {
    max(Int(usage.percentRemaining.rounded()), 0)
  }

  // The moment the remaining credits reach 0 at the average daily burn. It can fall after the reset date.
  public static func runOutDate(usage: CopilotUsage, now: Date) -> Date? {
    daysLeft(usage: usage, now: now).map { now.addingTimeInterval($0 * secondsPerDay) }
  }
}
