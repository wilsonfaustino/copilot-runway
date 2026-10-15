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
