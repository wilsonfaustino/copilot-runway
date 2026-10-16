import Core
import Testing

@Test func placeholderTitle() {
  #expect(MenuBarTitle.placeholder == "--% · --d")
}

@Test func titleShowsPercentRemainingAndWholeDaysLeft() {
  // 10 days in, 6000 used -> 50% left, exactly 10 days left.
  let title = MenuBarTitle.title(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-11T00:00:00Z"))
  #expect(title == "50% · 10d")
}

@Test func partialDaysRoundDown() {
  // 10 days in, 6100 used -> 9.67 days left.
  let title = MenuBarTitle.title(usage: makeUsage(creditsUsed: 6100), now: utcDate("2026-10-11T00:00:00Z"))
  #expect(title == "49% · 9d")
}

@Test func titleWithoutRunwayEstimate() {
  let title = MenuBarTitle.title(usage: makeUsage(creditsUsed: 0), now: utcDate("2026-10-11T00:00:00Z"))
  #expect(title == "100% · --d")
}

@Test func unlimitedPlanTitle() {
  let usage = makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true)
  #expect(MenuBarTitle.title(usage: usage, now: utcDate("2026-10-11T00:00:00Z")) == "∞")
}

@Test func errorTitles() {
  #expect(MenuBarTitle.title(error: .ghNotFound) == "gh missing")
  #expect(MenuBarTitle.title(error: .notLoggedIn) == "gh login")
  #expect(MenuBarTitle.title(error: .network) == "offline")
  #expect(MenuBarTitle.title(error: .httpStatus(500)) == "error")
  #expect(MenuBarTitle.title(error: .invalidResponse) == "error")
}

@Test func remainingFractionIsOneWhenNothingIsUsed() {
  #expect(MenuBarTitle.remainingFraction(usage: makeUsage(creditsUsed: 0)) == 1)
}

@Test func remainingFractionIsZeroWhenAllCreditsAreUsed() {
  #expect(MenuBarTitle.remainingFraction(usage: makeUsage(creditsUsed: 12000)) == 0)
}

@Test func remainingFractionMatchesPercentRemaining() {
  #expect(MenuBarTitle.remainingFraction(usage: makeUsage(creditsUsed: 6000)) == 0.5)
}

@Test func remainingFractionClampsOverLimitUsageToZero() {
  #expect(MenuBarTitle.remainingFraction(usage: makeUsage(creditsUsed: 13000)) == 0)
}

@Test func remainingFractionClampsAboveOneHundredPercent() {
  #expect(MenuBarTitle.remainingFraction(usage: makeUsage(creditsUsed: -600)) == 1)
}

@Test func remainingFractionIsZeroForZeroLimit() {
  #expect(MenuBarTitle.remainingFraction(usage: makeUsage(creditsUsed: 0, entitlement: 0)) == 0)
}

@Test func remainingFractionIsZeroWithoutUsage() {
  #expect(MenuBarTitle.remainingFraction(usage: nil) == 0)
}

@Test func remainingFractionIsOneForUnlimitedPlan() {
  let usage = makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true)
  #expect(MenuBarTitle.remainingFraction(usage: usage) == 1)
}

@Test func overLimitUsageShowsZeroPercentAndZeroDays() {
  // 20 days in, 12500 of 12000 used -> -4.17% and -0.8 days before the clamp.
  let title = MenuBarTitle.title(usage: makeUsage(creditsUsed: 12500), now: utcDate("2026-10-21T00:00:00Z"))
  #expect(title == "0% · 0d")
}
