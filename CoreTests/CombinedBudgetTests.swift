import Core
import Foundation
import Testing

private let combinedReset = utcDate("2026-12-01T00:00:00Z")
private let combinedNow = utcDate("2026-11-15T12:00:00Z")

private func isCloseToWithin1e9(_ left: Double, _ right: Double) -> Bool {
  abs(left - right) < 1e-9
}

private func copilotUsage(used: Double, remaining: Double, isUnlimited: Bool = false) -> QuotaUsage {
  QuotaUsage(
    creditsUsed: used, entitlement: 15000, creditsRemaining: remaining, percentRemaining: 31.8933,
    isUnlimited: isUnlimited, resetDate: combinedReset)
}

private func baseCopilot() -> QuotaUsage {
  copilotUsage(used: 10216, remaining: 4784)
}

private func baseCombined() throws -> CombinedBudget {
  try #require(CombinedBudget.make(copilot: baseCopilot(), portkeySpentUSD: 9.26, portkeyBudgetUSD: 50))
}

@Test func noBudgetGivesNil() {
  #expect(CombinedBudget.make(copilot: baseCopilot(), portkeySpentUSD: 9.26, portkeyBudgetUSD: nil) == nil)
  #expect(CombinedBudget.make(copilot: baseCopilot(), portkeySpentUSD: 9.26, portkeyBudgetUSD: 0) == nil)
  #expect(CombinedBudget.make(copilot: baseCopilot(), portkeySpentUSD: 9.26, portkeyBudgetUSD: -5) == nil)
}

@Test func unlimitedCopilotGivesNil() {
  let unlimited = copilotUsage(used: 0, remaining: 0, isUnlimited: true)
  #expect(CombinedBudget.make(copilot: unlimited, portkeySpentUSD: 9.26, portkeyBudgetUSD: 50) == nil)
}

@Test func combinesCopilotUSDAndPortkey() throws {
  let usage = try baseCombined().usage
  #expect(isCloseToWithin1e9(usage.creditsUsed, 111.42))
  #expect(isCloseToWithin1e9(usage.entitlement, 200))
  #expect(isCloseToWithin1e9(usage.creditsRemaining, 88.58))
  #expect(isCloseToWithin1e9(usage.percentRemaining, 44.29))
  #expect(usage.isUnlimited == false)
  #expect(usage.resetDate == combinedReset)
}

@Test func zeroPortkeySpendStillCombines() throws {
  let combined = try #require(CombinedBudget.make(copilot: baseCopilot(), portkeySpentUSD: 0, portkeyBudgetUSD: 50))
  #expect(isCloseToWithin1e9(combined.usage.entitlement, 200))
}

@Test func leftParts() throws {
  let combined = try baseCombined()
  let parts = combined.parts(mode: .left)
  #expect(isCloseToWithin1e9(parts.copilot, 0.2392))
  #expect(isCloseToWithin1e9(parts.portkey, 0.2037))
  let amounts = combined.amountsUSD(mode: .left)
  #expect(isCloseToWithin1e9(amounts.copilot, 47.84))
  #expect(isCloseToWithin1e9(amounts.portkey, 40.74))
}

@Test func spentParts() throws {
  let combined = try baseCombined()
  let parts = combined.parts(mode: .spent)
  #expect(isCloseToWithin1e9(parts.copilot, 0.5108))
  #expect(isCloseToWithin1e9(parts.portkey, 0.0463))
  #expect(isCloseToWithin1e9(parts.total, 0.5571))
  let amounts = combined.amountsUSD(mode: .spent)
  #expect(isCloseToWithin1e9(amounts.copilot, 102.16))
  #expect(isCloseToWithin1e9(amounts.portkey, 9.26))
}

@Test func portkeyOverBudget() throws {
  let copilot = copilotUsage(used: 10000, remaining: 5000)
  let combined = try #require(CombinedBudget.make(copilot: copilot, portkeySpentUSD: 60, portkeyBudgetUSD: 50))
  let parts = combined.parts(mode: .left)
  #expect(isCloseToWithin1e9(parts.copilot, 0.20))
  #expect(isCloseToWithin1e9(parts.portkey, 0))
  #expect(isCloseToWithin1e9(combined.amountsUSD(mode: .left).portkey, 0))
}

@Test func copilotOverLimit() throws {
  let copilot = copilotUsage(used: 16000, remaining: -1000)
  let combined = try #require(CombinedBudget.make(copilot: copilot, portkeySpentUSD: 10, portkeyBudgetUSD: 50))
  let parts = combined.parts(mode: .left)
  #expect(isCloseToWithin1e9(parts.copilot, 0))
  #expect(isCloseToWithin1e9(parts.portkey, 0.15))
}

@Test func combinedOverBudget() throws {
  let copilot = copilotUsage(used: 16000, remaining: -1000)
  let combined = try #require(CombinedBudget.make(copilot: copilot, portkeySpentUSD: 60, portkeyBudgetUSD: 50))
  #expect(isCloseToWithin1e9(combined.parts(mode: .left).total, 0))
  let spentParts = combined.parts(mode: .spent)
  #expect(isCloseToWithin1e9(spentParts.copilot, 0.80))
  #expect(isCloseToWithin1e9(spentParts.portkey, 0.20))
}

@Test func partsAddUpToGaugeFraction() throws {
  let cases: [(QuotaUsage, Double)] = [
    (baseCopilot(), 9.26),
    (copilotUsage(used: 10000, remaining: 5000), 60),
    (copilotUsage(used: 16000, remaining: -1000), 10),
    (copilotUsage(used: 16000, remaining: -1000), 60),
  ]
  for (copilot, portkeySpent) in cases {
    let combined = try #require(CombinedBudget.make(copilot: copilot, portkeySpentUSD: portkeySpent, portkeyBudgetUSD: 50))
    for mode in [GaugeMode.left, GaugeMode.spent] {
      let parts = combined.parts(mode: mode)
      #expect(isCloseToWithin1e9(parts.total, MenuBarTitle.gaugeFraction(usage: combined.usage, mode: mode)))
      #expect(parts.copilot >= 0)
      #expect(parts.portkey >= 0)
    }
  }
}

@Test func gaugePartsWithoutCombinedIsCopilotOnly() {
  let copilot = baseCopilot()
  let parts = MenuBarTitle.gaugeParts(usage: copilot, combined: nil, mode: .left)
  #expect(parts == GaugeParts(copilot: MenuBarTitle.gaugeFraction(usage: copilot, mode: .left), portkey: 0))
}

@Test func combinedTitle() throws {
  let combined = try baseCombined()
  #expect(MenuBarTitle.title(usage: combined.usage, now: combinedNow, mode: .left) == "44% · 11d")
}
