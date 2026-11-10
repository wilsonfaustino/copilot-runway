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
}
