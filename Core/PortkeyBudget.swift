import Foundation

// Maps the Portkey spend and monthly budget onto QuotaUsage, so Runway and RunwayHealth compute the Portkey
// runway with the Copilot rules. The caller passes the reset date: the Copilot reset with Copilot, the calendar
// month reset in Portkey-only mode. Amounts are USD, not credits.
public enum PortkeyBudget {
  // nil when there is no budget. A budget of 0 or less also counts as no budget.
  public static func usage(spentUSD: Double, budgetUSD: Double?, resetDate: Date) -> QuotaUsage? {
    guard let budgetUSD, budgetUSD > 0 else { return nil }
    let remainingUSD = budgetUSD - spentUSD
    return QuotaUsage(
      creditsUsed: spentUSD,
      entitlement: budgetUSD,
      creditsRemaining: remainingUSD,
      percentRemaining: remainingUSD / budgetUSD * 100,
      isUnlimited: false,
      resetDate: resetDate
    )
  }

  // The budget left per UTC date to the reset, for the Daily spend pace line. Today counts and the reset date does
  // not. Every date counts, also in workday mode, because the chart has one bar per UTC date. 0 over budget. nil
  // without a budget, or with no date left before the reset.
  public static func dailyPaceUSD(spentUSD: Double, budgetUSD: Double?, resetDate: Date, now: Date) -> Double? {
    guard let usage = usage(spentUSD: spentUSD, budgetUSD: budgetUSD, resetDate: resetDate) else { return nil }
    let datesUntilReset = RunwayDays.calendar.wholeUTCDayCount(fromDayOf: now, toDayOf: resetDate)
    guard datesUntilReset > 0 else { return nil }
    return max(usage.creditsRemaining, 0) / Double(datesUntilReset)
  }

  // With a budget and no spend yet, the budget reaches the reset. Otherwise the Runway.lastsTheCycle rule.
  public static func lastsTheCycle(usage: QuotaUsage, now: Date, days: RunwayDays = .calendar) -> Bool {
    if usage.creditsUsed <= 0 { return now < usage.resetDate }
    return Runway.lastsTheCycle(usage: usage, now: now, days: days)
  }

  public struct Status: Equatable, Sendable {
    public let text: String
    public let health: RunwayHealth

    public init(text: String, health: RunwayHealth) {
      self.text = text
      self.health = health
    }
  }

  // For example "$6.00 of $10.00 left, 15 days", or "lasts the cycle" when the money reaches the reset.
  // Over budget, the amount left stops at $0.00. nil without a budget.
  public static func status(
    spentUSD: Double, budgetUSD: Double?, resetDate: Date, now: Date, locale: Locale = .current,
    days: RunwayDays = .calendar
  ) -> Status? {
    guard let usage = usage(spentUSD: spentUSD, budgetUSD: budgetUSD, resetDate: resetDate) else { return nil }
    let leftText =
      "\(PortkeySpend.formatted(max(usage.creditsRemaining, 0), locale: locale)) of "
      + "\(PortkeySpend.formatted(usage.entitlement, locale: locale)) left"
    let daysText =
      if Runway.lastsTheCycle(usage: usage, now: now, days: days) {
        "lasts the cycle"
      } else {
        switch Runway.wholeDaysLeft(usage: usage, now: now, days: days) {
        case nil: "no spend yet"
        case let wholeDays?: "\(wholeDays) \(days.dayWord(count: wholeDays))"
        }
      }
    return Status(text: "\(leftText), \(daysText)", health: RunwayHealth(usage: usage, now: now, days: days))
  }

  public enum Entry: Equatable, Sendable {
    case noBudget
    case budget(Double)
    case refused
  }

  // Runway.wholeDaysLeft converts the days left to Int, which traps above Int.max. With this cap, a spend of
  // 1e-12 USD a day or more stays below it, and no real monthly budget comes near it.
  public static let maximumBudgetUSD: Double = 1_000_000

  // The Settings field. Empty or 0 means no budget. A negative amount, an amount above maximumBudgetUSD, or any
  // text that is not fully a number, is refused.
  public static func entry(from text: String, locale: Locale = .current) -> Entry {
    let trimmedText = text.trimmingCharacters(in: .whitespaces)
    if trimmedText.isEmpty { return .noBudget }
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    numberFormatter.locale = locale
    // number(from:) is nil unless the whole text is a number, so "10abc" does not save as 10.
    guard let amount = numberFormatter.number(from: trimmedText)?.doubleValue, (0...maximumBudgetUSD).contains(amount) else {
      return .refused
    }
    return amount == 0 ? .noBudget : .budget(amount)
  }

  // Hidden with no Portkey request this cycle and no budget, so Copilot-only users see no change.
  public static func showsBlock(requestCount: Int, budgetUSD: Double?) -> Bool {
    requestCount > 0 || (budgetUSD ?? 0) > 0
  }
}
