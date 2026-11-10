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

@Test func budgetStatusIsNilWithoutABudget() {
  #expect(PortkeyBudget.status(spentUSD: 4, budgetUSD: nil, resetDate: portkeyResetDate, now: portkeyNow) == nil)
}

@Test func budgetStatusUnderBudgetGivesDollarsAndDaysLeft() {
  let status = PortkeyBudget.status(spentUSD: 4, budgetUSD: 10, resetDate: portkeyResetDate, now: portkeyNow, locale: usLocale)
  #expect(status == PortkeyBudget.Status(text: "$6.00 of $10.00 left, 15 days", health: .short))
}

@Test func budgetStatusOverBudgetStopsAtZero() {
  let status = PortkeyBudget.status(spentUSD: 12, budgetUSD: 10, resetDate: portkeyResetDate, now: portkeyNow, locale: usLocale)
  #expect(status == PortkeyBudget.Status(text: "$0.00 of $10.00 left, 0 days", health: .critical))
}

@Test func budgetStatusWithNoSpendShowsTheFullBudget() {
  let status = PortkeyBudget.status(spentUSD: 0, budgetUSD: 10, resetDate: portkeyResetDate, now: portkeyNow, locale: usLocale)
  #expect(status == PortkeyBudget.Status(text: "$10.00 of $10.00 left, no spend yet", health: .healthy))
}

@Test func budgetStatusUsesSingularDay() {
  // 5 of 5.60 USD in 10 days: 0.5 USD/day, 0.60 USD left, 1.2 days.
  let status = PortkeyBudget.status(spentUSD: 5, budgetUSD: 5.6, resetDate: portkeyResetDate, now: portkeyNow, locale: usLocale)
  #expect(status?.text == "$0.60 of $5.60 left, 1 day")
}

// Copilot-only users see no Portkey block.
@Test func blockIsHiddenWithNoRequestsAndNoBudget() {
  #expect(PortkeyBudget.showsBlock(requestCount: 0, budgetUSD: nil) == false)
  #expect(PortkeyBudget.showsBlock(requestCount: 0, budgetUSD: 0) == false)
}

@Test func emptyBudgetTextMeansNoBudget() {
  #expect(PortkeyBudget.entry(from: "", locale: usLocale) == .noBudget)
  #expect(PortkeyBudget.entry(from: "  ", locale: usLocale) == .noBudget)
  #expect(PortkeyBudget.entry(from: "0", locale: usLocale) == .noBudget)
}

@Test func budgetTextGivesTheBudget() {
  #expect(PortkeyBudget.entry(from: "25", locale: usLocale) == .budget(25))
  #expect(PortkeyBudget.entry(from: " 1,000.50 ", locale: usLocale) == .budget(1000.5))
  #expect(PortkeyBudget.entry(from: "12,5", locale: Locale(identifier: "pt_BR")) == .budget(12.5))
}

@Test func negativeOrNonNumberBudgetTextIsRefused() {
  #expect(PortkeyBudget.entry(from: "-5", locale: usLocale) == .refused)
  #expect(PortkeyBudget.entry(from: "ten", locale: usLocale) == .refused)
}

@Test func blockShowsWithRequestsOrBudget() {
  #expect(PortkeyBudget.showsBlock(requestCount: 3, budgetUSD: nil))
  #expect(PortkeyBudget.showsBlock(requestCount: 0, budgetUSD: 25))
}
