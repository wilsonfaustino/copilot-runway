import Core
import Foundation
import Testing

// The Copilot cycle: reset 2026-11-01, so the cycle starts 2026-10-01 and now is 10 days in.
private let portkeyResetDate = utcDate("2026-11-01T00:00:00Z")
private let portkeyNow = utcDate("2026-10-11T00:00:00Z")

@Test func noBudgetGivesNoUsage() {
  #expect(PortkeyBudget.usage(spentUSD: 4, budgetUSD: nil, resetDate: portkeyResetDate) == nil)
}

// A budget of 0 would divide by 0 in the percent left, so it counts as no budget.
@Test func zeroBudgetGivesNoUsage() {
  #expect(PortkeyBudget.usage(spentUSD: 4, budgetUSD: 0, resetDate: portkeyResetDate) == nil)
}

@Test func underBudgetWithEarlyRunOutIsShort() throws {
  // 4 of 10 USD in 10 days: 0.4 USD/day, 6 USD left, 15 days, run-out 2026-10-26.
  let usage = try #require(PortkeyBudget.usage(spentUSD: 4, budgetUSD: 10, resetDate: portkeyResetDate))
  #expect(usage.creditsRemaining == 6)
  #expect(usage.entitlement == 10)
  #expect(usage.resetDate == portkeyResetDate)
  #expect(Runway.wholePercentRemaining(usage: usage) == 60)
  #expect(Runway.wholeDaysLeft(usage: usage, now: portkeyNow) == 15)
  #expect(RunwayHealth(usage: usage, now: portkeyNow) == .short)
}

@Test func underBudgetPastResetIsHealthy() throws {
  // 1 of 10 USD in 10 days: 0.1 USD/day, 9 USD left, 90 days.
  let usage = try #require(PortkeyBudget.usage(spentUSD: 1, budgetUSD: 10, resetDate: portkeyResetDate))
  #expect(usage.creditsRemaining == 9)
  #expect(Runway.wholeDaysLeft(usage: usage, now: portkeyNow) == 90)
  #expect(RunwayHealth(usage: usage, now: portkeyNow) == .healthy)
}

@Test func overBudgetGivesZeroDaysAndCritical() throws {
  let usage = try #require(PortkeyBudget.usage(spentUSD: 12, budgetUSD: 10, resetDate: portkeyResetDate))
  #expect(usage.creditsRemaining == -2)
  #expect(Runway.wholePercentRemaining(usage: usage) == 0)
  #expect(Runway.wholeDaysLeft(usage: usage, now: portkeyNow) == 0)
  #expect(RunwayHealth(usage: usage, now: portkeyNow) == .critical)
}

@Test func budgetWithNoSpendLeavesTheFullBudget() throws {
  let usage = try #require(PortkeyBudget.usage(spentUSD: 0, budgetUSD: 10, resetDate: portkeyResetDate))
  #expect(usage.creditsRemaining == 10)
  #expect(Runway.wholePercentRemaining(usage: usage) == 100)
  #expect(Runway.wholeDaysLeft(usage: usage, now: portkeyNow) == nil)
  #expect(RunwayHealth(usage: usage, now: portkeyNow) == .healthy)
}
