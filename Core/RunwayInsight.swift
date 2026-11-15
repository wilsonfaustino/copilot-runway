import Foundation

// What the headroom and popover lines count: Copilot credits, or the US dollars of the combined budget.
public enum BudgetUnit: Sendable {
  case credits
  case usd
}

public enum RunwayInsight {
  // When the credits run out against the reset. Stale usage from a past cycle has no outlook, and an unlimited plan
  // or a cycle with no burn has no run-out.
  private enum RunOutOutlook {
    case pastReset
    case beforeReset(runOutDate: Date, daysBeforeReset: Int)
  }

  private static func runOutOutlook(usage: QuotaUsage, now: Date, days: RunwayDays) -> RunOutOutlook? {
    guard now < usage.resetDate, let estimatedRunOut = Runway.runOutDate(usage: usage, now: now, days: days) else { return nil }
    // Overage gives a run-out in the past, but the credits ran out by now at the latest.
    let runOutDate = max(estimatedRunOut, now)
    guard runOutDate < usage.resetDate else { return .pastReset }
    // Count calendar days in UTC so the number matches the two dates in the sentence, in both day modes.
    let calendar = Runway.utcCalendar
    let daysBeforeReset = calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: runOutDate), to: calendar.startOfDay(for: usage.resetDate)
    ).day ?? 0
    return .beforeReset(runOutDate: runOutDate, daysBeforeReset: daysBeforeReset)
  }

  public static func runOutSentence(usage: QuotaUsage, now: Date, locale: Locale = .current, days: RunwayDays = .calendar) -> String? {
    runOutSentence(usage: usage, now: now, locale: locale, days: days, lastsText: "your credits last", runsOutText: "you run out")
  }

  private static func runOutSentence(
    usage: QuotaUsage, now: Date, locale: Locale, days: RunwayDays, lastsText: String, runsOutText: String
  ) -> String? {
    let resetText = day(usage.resetDate, locale: locale)
    switch runOutOutlook(usage: usage, now: now, days: days) {
    case nil: return nil
    case .pastReset?: return "At this pace \(lastsText) past the reset on \(resetText)."
    case .beforeReset(let runOutDate, let daysBeforeReset)?:
      let daysText = daysBeforeReset == 1 ? "1 day" : "\(daysBeforeReset) days"
      return "At this pace \(runsOutText) on \(day(runOutDate, locale: locale)), \(daysText) before the reset on \(resetText)."
    }
  }

  public static func limitSentence(usage: QuotaUsage, locale: Locale = .current) -> String {
    "You used all credits for this cycle. Resets \(day(usage.resetDate, locale: locale))."
  }

  // The runOutSentence and limitSentence wording for a Portkey budget from PortkeyBudget.usage.
  static func portkeyRunOutSentence(usage: QuotaUsage, now: Date, locale: Locale, days: RunwayDays) -> String? {
    runOutSentence(
      usage: usage, now: now, locale: locale, days: days,
      lastsText: "your Portkey budget lasts", runsOutText: "your Portkey budget runs out")
  }

  static func portkeyLimitSentence(usage: QuotaUsage, locale: Locale) -> String {
    "You used all of your Portkey budget for this cycle. Resets \(day(usage.resetDate, locale: locale))."
  }

  // The highest average burn from now on that still reaches the reset with credits left.
  public static func requiredDailyBurn(usage: QuotaUsage, now: Date, days: RunwayDays = .calendar) -> Double? {
    guard !usage.isUnlimited, now < usage.resetDate else { return nil }
    let daysUntilReset = days.dayCount(from: now, to: usage.resetDate)
    guard daysUntilReset > 0 else { return nil }
    return max(usage.creditsRemaining, 0) / daysUntilReset
  }

  // "N credits/day of headroom" or "N credits/day over budget". nil when Runway.dailyHeadroom is nil.
  // With .usd the usage is in dollars and the amount reads as "$N/day".
  public static func headroomText(
    usage: QuotaUsage, now: Date, locale: Locale = .current, days: RunwayDays = .calendar, unit: BudgetUnit = .credits
  ) -> String? {
    guard let headroom = Runway.dailyHeadroom(usage: usage, now: now, days: days) else { return nil }
    let amountText =
      switch unit {
      case .credits: "\(Credits.formatted(abs(headroom), locale: locale)) credits"
      case .usd: PortkeySpend.formatted(abs(headroom), locale: locale)
      }
    let dayWord = days.dayWord()
    return headroom >= 0 ? "\(amountText)/\(dayWord) of headroom" : "\(amountText)/\(dayWord) over budget"
  }

  // The category with the most local credits and its rounded share of them. nil when no category has credits.
  public static func topCategoryShare(categoryCredits: [CategoryCredits]) -> (category: TaskCategory, percent: Int)? {
    let total = categoryCredits.reduce(0) { $0 + $1.credits }
    guard total > 0, let top = categoryCredits.max(by: { $0.credits < $1.credits }) else { return nil }
    return (top.category, Credits.sharePercent(top.credits, of: total))
  }

  // The dashboard banner. The headline names the state, the detail adds what to do next and the top category.
  // A past cycle with credits used has no run-out sentence, so it falls through to the reset sentence.
  // With a combined budget the run-out, target burn and headroom count its US dollars, and one more sentence
  // gives the average burn of Copilot and of Portkey, so the user sees which one to cut.
  public static func banner(
    usage: QuotaUsage,
    errorMessage: String?,
    categoryCredits: [CategoryCredits],
    now: Date,
    locale: Locale = .current,
    days: RunwayDays = .calendar,
    combined: CombinedBudget? = nil
  ) -> (headline: String, detail: String) {
    var detailSentences: [String] = []
    let headline: String
    let budgetUsage = combined?.usage ?? usage
    let unit: BudgetUnit = combined == nil ? .credits : .usd
    if let errorMessage {
      headline = errorMessage
      detailSentences.append("The numbers below are from the last good refresh.")
    } else if usage.isUnlimited {
      headline = "Unlimited plan."
      detailSentences.append("\(Credits.formatted(usage.creditsUsed, locale: locale)) credits used this cycle.")
    } else if let runOutSentence = runOutSentence(
      usage: budgetUsage, now: now, locale: locale, days: days,
      lastsText: combined == nil ? "your credits last" : "your combined budget lasts", runsOutText: "you run out")
    {
      headline = runOutSentence
      if let runOutDate = Runway.runOutDate(usage: budgetUsage, now: now, days: days), runOutDate < budgetUsage.resetDate,
        let targetText = targetBurnText(usage: budgetUsage, now: now, locale: locale, days: days, unit: unit)
      {
        detailSentences.append("To reach \(day(budgetUsage.resetDate, locale: locale)), keep the burn under \(targetText).")
      }
      if let headroomText = headroomText(usage: budgetUsage, now: now, locale: locale, days: days, unit: unit) {
        detailSentences.append("\(headroomText).")
      }
      if let combined {
        detailSentences.append(providerAveragesSentence(combined: combined, now: now, locale: locale, days: days))
      }
    } else {
      headline = combined == nil ? "No credits used yet this cycle." : "Nothing spent yet this cycle."
      detailSentences.append("Resets \(day(budgetUsage.resetDate, locale: locale)).")
    }
    if let topShare = topCategoryShare(categoryCredits: categoryCredits) {
      detailSentences.append("\(topShare.category.displayName) turns use \(topShare.percent)% of local credits.")
    }
    return (headline, detailSentences.joined(separator: " "))
  }

  // Rounded down (whole credits, or cents), so the burn stays under the target. A target of 0 is not a useful
  // instruction, so it gives nil.
  private static func targetBurnText(
    usage: QuotaUsage, now: Date, locale: Locale, days: RunwayDays, unit: BudgetUnit
  ) -> String? {
    guard let requiredBurn = requiredDailyBurn(usage: usage, now: now, days: days) else { return nil }
    switch unit {
    case .credits:
      let targetCredits = Int(requiredBurn.rounded(.down))
      return targetCredits > 0 ? "\(targetCredits.formatted(.number.locale(locale))) credits/\(days.dayWord())" : nil
    case .usd:
      let targetUSD = (requiredBurn * 100).rounded(.down) / 100
      return targetUSD > 0 ? "\(PortkeySpend.formatted(targetUSD, locale: locale))/\(days.dayWord())" : nil
    }
  }

  // For example "Copilot averages $7.05/day and Portkey $0.64/day."
  private static func providerAveragesSentence(
    combined: CombinedBudget, now: Date, locale: Locale, days: RunwayDays
  ) -> String {
    let spentUSD = combined.amountsUSD(mode: .spent)
    let resetDate = combined.usage.resetDate
    let copilotBurn = Runway.averageDailyBurn(credits: spentUSD.copilot, resetDate: resetDate, now: now, days: days)
    let portkeyBurn = Runway.averageDailyBurn(credits: spentUSD.portkey, resetDate: resetDate, now: now, days: days)
    let dayWord = days.dayWord()
    return "Copilot averages \(PortkeySpend.formatted(copilotBurn, locale: locale))/\(dayWord) "
      + "and Portkey \(PortkeySpend.formatted(portkeyBurn, locale: locale))/\(dayWord)."
  }

  // The lines under the popover runway figure. Each line must fit about 30 characters next to the ring,
  // so the headroom text goes on a second line. nil when there is nothing useful to say.
  public static func popoverSentence(
    usage: QuotaUsage, now: Date, locale: Locale = .current, days: RunwayDays = .calendar, unit: BudgetUnit = .credits
  ) -> String? {
    let headroomLine = headroomText(usage: usage, now: now, locale: locale, days: days, unit: unit).map { "\n\($0)." } ?? ""
    switch runOutOutlook(usage: usage, now: now, days: days) {
    // The figure above already says "Lasts the cycle" with the reset day, so only the headroom line is left.
    case .pastReset?: return headroomText(usage: usage, now: now, locale: locale, days: days, unit: unit).map { "\($0)." }
    case .beforeReset(let runOutDate, let daysBeforeReset)?:
      let daysText = daysBeforeReset == 1 ? "1 day" : "\(daysBeforeReset) days"
      return "Runs out \(day(runOutDate, locale: locale)), \(daysText) early.\(headroomLine)"
    case nil: break
    }
    if usage.isUnlimited { return "Unlimited plan, no run-out." }
    if usage.creditsUsed == 0 { return unit == .usd ? "Nothing spent yet." : "No credits used yet." }
    return nil
  }

  public static func resetCaption(usage: QuotaUsage, locale: Locale = .current) -> String {
    "Resets \(day(usage.resetDate, locale: locale))"
  }

  // The billing cycle resets at midnight UTC, so dates show the UTC day.
  static func day(_ date: Date, locale: Locale) -> String {
    var dayStyle = Date.FormatStyle(locale: locale, calendar: Runway.utcCalendar, timeZone: Runway.utcCalendar.timeZone)
    dayStyle = dayStyle.month(.abbreviated).day()
    return date.formatted(dayStyle)
  }
}
