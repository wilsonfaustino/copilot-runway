import Foundation

public enum RunwayInsight {
  // Stale usage from a past cycle has no estimate, and an unlimited plan or a cycle with no burn has no run-out.
  public static func runOutSentence(usage: CopilotUsage, now: Date, locale: Locale = .current) -> String? {
    guard now < usage.resetDate, let estimatedRunOut = Runway.runOutDate(usage: usage, now: now) else { return nil }
    // Overage gives a run-out in the past, but the credits ran out by now at the latest.
    let runOutDate = max(estimatedRunOut, now)
    let resetText = day(usage.resetDate, locale: locale)
    guard runOutDate < usage.resetDate else {
      return "At this pace your credits last past the reset on \(resetText)."
    }
    // Count calendar days in UTC so the number matches the two dates in the sentence.
    let calendar = Runway.utcCalendar
    let daysBeforeReset = calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: runOutDate), to: calendar.startOfDay(for: usage.resetDate)
    ).day ?? 0
    let daysText = daysBeforeReset == 1 ? "1 day" : "\(daysBeforeReset) days"
    return "At this pace you run out on \(day(runOutDate, locale: locale)), \(daysText) before the reset on \(resetText)."
  }

  // The highest average burn from now on that still reaches the reset with credits left.
  public static func requiredDailyBurn(usage: CopilotUsage, now: Date) -> Double? {
    guard !usage.isUnlimited, now < usage.resetDate else { return nil }
    let daysUntilReset = usage.resetDate.timeIntervalSince(now) / Runway.secondsPerDay
    return max(usage.creditsRemaining, 0) / daysUntilReset
  }

  // The share of GitHub credits that no local session explains. nil when it rounds to 0% or local sessions
  // show more than GitHub, for example after a price table overestimate.
  public static func percentNotInLocalSessions(creditsUsed: Double, localCredits: Double) -> Int? {
    guard creditsUsed > 0, localCredits < creditsUsed else { return nil }
    let percent = Int(((creditsUsed - localCredits) / creditsUsed * 100).rounded())
    return percent > 0 ? percent : nil
  }

  // The category with the most local credits and its rounded share of them. nil when no category has credits.
  public static func topCategoryShare(categoryCredits: [CategoryCredits]) -> (category: TaskCategory, percent: Int)? {
    let total = categoryCredits.reduce(0) { $0 + $1.credits }
    guard total > 0, let top = categoryCredits.max(by: { $0.credits < $1.credits }) else { return nil }
    return (top.category, Int((top.credits / total * 100).rounded()))
  }

  // The billing cycle resets at midnight UTC, so dates show the UTC day.
  static func day(_ date: Date, locale: Locale) -> String {
    var dayStyle = Date.FormatStyle(locale: locale, calendar: Runway.utcCalendar, timeZone: Runway.utcCalendar.timeZone)
    dayStyle = dayStyle.month(.abbreviated).day()
    return date.formatted(dayStyle)
  }
}
