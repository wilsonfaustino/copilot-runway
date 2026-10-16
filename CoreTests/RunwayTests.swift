import Core
import Foundation
import Testing

func makeUsage(creditsUsed: Double, entitlement: Double = 12000, isUnlimited: Bool = false) -> CopilotUsage {
  let creditsRemaining = entitlement - creditsUsed
  return CopilotUsage(
    creditsUsed: creditsUsed,
    entitlement: entitlement,
    creditsRemaining: creditsRemaining,
    percentRemaining: entitlement > 0 ? creditsRemaining / entitlement * 100 : 0,
    isUnlimited: isUnlimited,
    resetDate: utcDate("2026-11-01T00:00:00Z")
  )
}

@Test func cycleStartsOneMonthBeforeReset() {
  #expect(Runway.cycleStart(resetDate: utcDate("2026-11-01T00:00:00Z")) == utcDate("2026-10-01T00:00:00Z"))
}

@Test func averageDailyBurnIsUsedOverElapsedDays() {
  // 10 days into the cycle, 6000 used -> 600/day.
  let averageDailyBurn = Runway.averageDailyBurn(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-11T00:00:00Z"))
  #expect(abs(averageDailyBurn - 600) < 0.0001)
}

@Test func averageDailyBurnFromCreditsMatchesUsageOverload() {
  let usage = makeUsage(creditsUsed: 6000)
  let now = utcDate("2026-10-11T00:00:00Z")
  let fromCredits = Runway.averageDailyBurn(credits: 6000, resetDate: usage.resetDate, now: now)
  #expect(fromCredits == Runway.averageDailyBurn(usage: usage, now: now))
  // 10 days into the cycle, 6000 credits -> 600/day.
  #expect(abs(fromCredits - 600) < 0.0001)
}

@Test func daysLeftIsRemainingOverAverageDailyBurn() throws {
  // 10 days into the cycle, 6000 used: burn 600/day, 6000 left -> 10 days.
  let daysLeft = try #require(Runway.daysLeft(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-11T00:00:00Z")))
  #expect(abs(daysLeft - 10) < 0.0001)
}

@Test func firstDayOfCycleCountsAsOneFullDay() throws {
  let daysLeft = try #require(Runway.daysLeft(usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-10-01T01:00:00Z")))
  #expect(abs(daysLeft - 11) < 0.0001)
}

@Test func noBurnMeansNoRunwayEstimate() {
  #expect(Runway.daysLeft(usage: makeUsage(creditsUsed: 0), now: utcDate("2026-10-11T00:00:00Z")) == nil)
}

@Test func unlimitedPlanHasNoRunwayEstimate() {
  let usage = makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true)
  #expect(Runway.daysLeft(usage: usage, now: utcDate("2026-10-11T00:00:00Z")) == nil)
}

@Test func runOutDateIsNowPlusDaysLeft() throws {
  // 10 days into the cycle, 6000 used: 10 days left.
  let runOutDate = try #require(Runway.runOutDate(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-11T00:00:00Z")))
  #expect(runOutDate == utcDate("2026-10-21T00:00:00Z"))
}

@Test func runOutDateCanFallAfterReset() throws {
  // 10 days into the cycle, 1000 used: burn 100/day, 11000 left -> 110 days.
  let runOutDate = try #require(Runway.runOutDate(usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-10-11T00:00:00Z")))
  #expect(runOutDate == utcDate("2027-01-29T00:00:00Z"))
}

@Test func noRunOutDateWithoutBurnOrLimit() {
  let now = utcDate("2026-10-11T00:00:00Z")
  #expect(Runway.runOutDate(usage: makeUsage(creditsUsed: 0), now: now) == nil)
  #expect(Runway.runOutDate(usage: makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true), now: now) == nil)
}

@Test func wholeDaysLeftRoundsDown() {
  // 10 days in, 6100 used -> 9.67 days left.
  #expect(Runway.wholeDaysLeft(usage: makeUsage(creditsUsed: 6100), now: utcDate("2026-10-11T00:00:00Z")) == 9)
}

@Test func wholeDaysLeftClampsOverLimitUsageToZero() {
  // 20 days in, 12500 of 12000 used -> -0.8 days before the clamp.
  #expect(Runway.wholeDaysLeft(usage: makeUsage(creditsUsed: 12500), now: utcDate("2026-10-21T00:00:00Z")) == 0)
}

@Test func wholeDaysLeftIsNilWithoutBurn() {
  #expect(Runway.wholeDaysLeft(usage: makeUsage(creditsUsed: 0), now: utcDate("2026-10-11T00:00:00Z")) == nil)
}

@Test func wholePercentRemainingRounds() {
  // 6100 of 12000 used -> 49.17% left.
  #expect(Runway.wholePercentRemaining(usage: makeUsage(creditsUsed: 6100)) == 49)
}

@Test func wholePercentRemainingClampsOverLimitUsageToZero() {
  // 12500 of 12000 used -> -4.17% before the clamp.
  #expect(Runway.wholePercentRemaining(usage: makeUsage(creditsUsed: 12500)) == 0)
}
