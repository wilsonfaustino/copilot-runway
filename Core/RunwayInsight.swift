import Foundation

public enum RunwayInsight {
  // When the credits run out against the reset. Stale usage from a past cycle has no outlook, and an unlimited plan
  // or a cycle with no burn has no run-out.
  private enum RunOutOutlook {
    case pastReset
    case beforeReset(runOutDate: Date, daysBeforeReset: Int)
  }

  private static func runOutOutlook(usage: CopilotUsage, now: Date) -> RunOutOutlook? {
    guard now < usage.resetDate, let estimatedRunOut = Runway.runOutDate(usage: usage, now: now) else { return nil }
    // Overage gives a run-out in the past, but the credits ran out by now at the latest.
    let runOutDate = max(estimatedRunOut, now)
    guard runOutDate < usage.resetDate else { return .pastReset }
    // Count calendar days in UTC so the number matches the two dates in the sentence.
    let calendar = Runway.utcCalendar
    let daysBeforeReset = calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: runOutDate), to: calendar.startOfDay(for: usage.resetDate)
    ).day ?? 0
    return .beforeReset(runOutDate: runOutDate, daysBeforeReset: daysBeforeReset)
  }

  public static func runOutSentence(usage: CopilotUsage, now: Date, locale: Locale = .current) -> String? {
    let resetText = day(usage.resetDate, locale: locale)
    switch runOutOutlook(usage: usage, now: now) {
    case nil: return nil
    case .pastReset?: return "At this pace your credits last past the reset on \(resetText)."
    case .beforeReset(let runOutDate, let daysBeforeReset)?:
      let daysText = daysBeforeReset == 1 ? "1 day" : "\(daysBeforeReset) days"
      return "At this pace you run out on \(day(runOutDate, locale: locale)), \(daysText) before the reset on \(resetText)."
    }
  }

  public static func limitSentence(usage: CopilotUsage, locale: Locale = .current) -> String {
    "You used all credits for this cycle. Resets \(day(usage.resetDate, locale: locale))."
  }

  // The highest average burn from now on that still reaches the reset with credits left.
  public static func requiredDailyBurn(usage: CopilotUsage, now: Date) -> Double? {
    guard !usage.isUnlimited, now < usage.resetDate else { return nil }
    let daysUntilReset = usage.resetDate.timeIntervalSince(now) / Runway.secondsPerDay
    return max(usage.creditsRemaining, 0) / daysUntilReset
  }

  // Copilot code review bills the PR author, but no local session records it. nil when no review ran.
  public static func copilotReviewSentence(count: Int) -> String? {
    switch count {
    case ..<1: nil
    case 1: "1 Copilot code review ran on your PRs this cycle. It uses credits that local sessions do not show."
    default: "\(count) Copilot code reviews ran on your PRs this cycle. They use credits that local sessions do not show."
    }
  }

  // The popover caption under the By model legend. nil when no review ran.
  public static func copilotReviewCaption(count: Int) -> String? {
    switch count {
    case ..<1: nil
    case 1: "1 Copilot code review ran on your PRs this cycle."
    default: "\(count) Copilot code reviews ran on your PRs this cycle."
    }
  }

  // The category with the most local credits and its rounded share of them. nil when no category has credits.
  public static func topCategoryShare(categoryCredits: [CategoryCredits]) -> (category: TaskCategory, percent: Int)? {
    let total = categoryCredits.reduce(0) { $0 + $1.credits }
    guard total > 0, let top = categoryCredits.max(by: { $0.credits < $1.credits }) else { return nil }
    return (top.category, Credits.sharePercent(top.credits, of: total))
  }

  // The dashboard banner. The headline names the state, the detail adds what to do next and the top category.
  // A past cycle with credits used has no run-out sentence, so it falls through to the reset sentence.
  public static func banner(
    usage: CopilotUsage,
    errorMessage: String?,
    categoryCredits: [CategoryCredits],
    now: Date,
    locale: Locale = .current
  ) -> (headline: String, detail: String) {
    var detailSentences: [String] = []
    let headline: String
    if let errorMessage {
      headline = errorMessage
      detailSentences.append("The numbers below are from the last good refresh.")
    } else if usage.isUnlimited {
      headline = "Unlimited plan."
      detailSentences.append("\(Credits.formatted(usage.creditsUsed, locale: locale)) credits used this cycle.")
    } else if let runOutSentence = runOutSentence(usage: usage, now: now, locale: locale) {
      headline = runOutSentence
      // Rounded down, so the burn stays under the target. A target of 0 is not a useful instruction.
      let targetBurn = requiredDailyBurn(usage: usage, now: now).map { Int($0.rounded(.down)) } ?? 0
      if let runOutDate = Runway.runOutDate(usage: usage, now: now), runOutDate < usage.resetDate, targetBurn > 0 {
        detailSentences.append(
          "To reach \(day(usage.resetDate, locale: locale)), keep the burn under \(targetBurn.formatted(.number.locale(locale))) credits/day."
        )
      }
    } else {
      headline = "No credits used yet this cycle."
      detailSentences.append("Resets \(day(usage.resetDate, locale: locale)).")
    }
    if let topShare = topCategoryShare(categoryCredits: categoryCredits) {
      detailSentences.append("\(topShare.category.displayName) turns use \(topShare.percent)% of local credits.")
    }
    return (headline, detailSentences.joined(separator: " "))
  }

  // The one line under the popover runway figure. It must fit about 30 characters next to the ring.
  // nil when there is nothing useful to say.
  public static func popoverSentence(usage: CopilotUsage, now: Date, locale: Locale = .current) -> String? {
    switch runOutOutlook(usage: usage, now: now) {
    case .pastReset?: return "Lasts past the \(day(usage.resetDate, locale: locale)) reset."
    case .beforeReset(let runOutDate, let daysBeforeReset)?:
      let daysText = daysBeforeReset == 1 ? "1 day" : "\(daysBeforeReset) days"
      return "Runs out \(day(runOutDate, locale: locale)), \(daysText) early."
    case nil: break
    }
    if usage.isUnlimited { return "Unlimited plan, no run-out." }
    if usage.creditsUsed == 0 { return "No credits used yet." }
    return nil
  }

  // The billing cycle resets at midnight UTC, so dates show the UTC day.
  static func day(_ date: Date, locale: Locale) -> String {
    var dayStyle = Date.FormatStyle(locale: locale, calendar: Runway.utcCalendar, timeZone: Runway.utcCalendar.timeZone)
    dayStyle = dayStyle.month(.abbreviated).day()
    return date.formatted(dayStyle)
  }
}
