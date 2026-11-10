import Foundation

// Maps the Portkey spend and monthly budget onto CopilotUsage, so Runway and RunwayHealth compute the Portkey
// runway with the Copilot rules. The Portkey cycle is the Copilot cycle. Amounts are USD, not credits.
public enum PortkeyBudget {
  // nil when there is no budget. A budget of 0 or less also counts as no budget.
  public static func usage(spentUSD: Double, budgetUSD: Double?, resetDate: Date) -> CopilotUsage? {
    guard let budgetUSD, budgetUSD > 0 else { return nil }
    let remainingUSD = budgetUSD - spentUSD
    return CopilotUsage(
      creditsUsed: spentUSD,
      entitlement: budgetUSD,
      creditsRemaining: remainingUSD,
      percentRemaining: remainingUSD / budgetUSD * 100,
      isUnlimited: false,
      resetDate: resetDate
    )
  }

  public struct Status: Equatable, Sendable {
    public let text: String
    public let health: RunwayHealth

    public init(text: String, health: RunwayHealth) {
      self.text = text
      self.health = health
    }
  }

  // For example "$6.00 of $10.00 left, 15 days". Over budget, the amount left stops at $0.00. nil without a budget.
  public static func status(
    spentUSD: Double, budgetUSD: Double?, resetDate: Date, now: Date, locale: Locale = .current
  ) -> Status? {
    guard let usage = usage(spentUSD: spentUSD, budgetUSD: budgetUSD, resetDate: resetDate) else { return nil }
    let leftText =
      "\(PortkeySpend.formatted(max(usage.creditsRemaining, 0), locale: locale)) of "
      + "\(PortkeySpend.formatted(usage.entitlement, locale: locale)) left"
    let daysText =
      switch Runway.wholeDaysLeft(usage: usage, now: now) {
      case nil: "no spend yet"
      case 1: "1 day"
      case let wholeDays?: "\(wholeDays) days"
      }
    return Status(text: "\(leftText), \(daysText)", health: RunwayHealth(usage: usage, now: now))
  }

  public enum Entry: Equatable, Sendable {
    case noBudget
    case budget(Double)
    case refused
  }

  // The Settings field. Empty or 0 means no budget. A negative amount or other text is refused.
  public static func entry(from text: String, locale: Locale = .current) -> Entry {
    let trimmedText = text.trimmingCharacters(in: .whitespaces)
    if trimmedText.isEmpty { return .noBudget }
    guard let amount = try? Double(trimmedText, format: .number.locale(locale)), amount >= 0 else { return .refused }
    return amount == 0 ? .noBudget : .budget(amount)
  }

  // Hidden with no Portkey request this cycle and no budget, so Copilot-only users see no change.
  public static func showsBlock(requestCount: Int, budgetUSD: Double?) -> Bool {
    requestCount > 0 || (budgetUSD ?? 0) > 0
  }
}
