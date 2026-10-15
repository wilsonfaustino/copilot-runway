import Foundation

public enum Runway {
  static let secondsPerDay: Double = 86_400

  public static func cycleStart(resetDate: Date) -> Date {
    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = TimeZone(identifier: "UTC")!
    return utcCalendar.date(byAdding: .month, value: -1, to: resetDate)!
  }

  // daysLeft = remaining / averageDailyBurn over the current billing cycle.
  // Elapsed time counts as at least one day, so the first hours of a cycle do not inflate the burn.
  public static func daysLeft(usage: CopilotUsage, now: Date) -> Double? {
    guard !usage.isUnlimited, usage.creditsUsed > 0 else { return nil }
    let elapsedDays = now.timeIntervalSince(cycleStart(resetDate: usage.resetDate)) / secondsPerDay
    let averageDailyBurn = usage.creditsUsed / max(elapsedDays, 1)
    return usage.creditsRemaining / averageDailyBurn
  }
}
