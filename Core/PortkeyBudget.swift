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
