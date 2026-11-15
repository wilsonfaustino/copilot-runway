#if DEBUG
import Foundation

// Fake Portkey usage for the Debug-only `-portkeyNoticeDrill` launch argument. A budget drains in steps that each
// add one Portkey notice: 80% used, short, critical, then reached. No value comes from a real setting or file.
public enum PortkeyNoticeDrill {
  static let budgetUSD = 120.0
  // With the reset 3 days away, 25 to 28 days have passed, so 96 USD lasts past the reset, 112 USD runs out in
  // 1.8 to 2 days, 118 USD in under 1 day, and 125 USD is over the budget.
  static let spentUSDSteps = [96.0, 112.0, 118.0, 125.0]
  static let daysToReset = 3.0

  public static func usages(now: Date) -> [QuotaUsage] {
    let resetDate = now.addingTimeInterval(daysToReset * 24 * 60 * 60)
    return spentUSDSteps.compactMap { PortkeyBudget.usage(spentUSD: $0, budgetUSD: budgetUSD, resetDate: resetDate) }
  }
}
#endif
