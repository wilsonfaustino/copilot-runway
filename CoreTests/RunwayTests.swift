import Core
import Foundation
import Testing

func makeUsage(
  creditsUsed: Double, entitlement: Double = 12000, isUnlimited: Bool = false,
  resetDate: Date = utcDate("2026-11-01T00:00:00Z")
) -> QuotaUsage {
  let creditsRemaining = entitlement - creditsUsed
  return QuotaUsage(
    creditsUsed: creditsUsed,
    entitlement: entitlement,
    creditsRemaining: creditsRemaining,
    percentRemaining: entitlement > 0 ? creditsRemaining / entitlement * 100 : 0,
    isUnlimited: isUnlimited,
    resetDate: resetDate
  )
}

@Test func cycleStartsOneMonthBeforeReset() {
  #expect(Runway.cycleStart(resetDate: utcDate("2026-11-01T00:00:00Z")) == utcDate("2026-10-01T00:00:00Z"))
}

@Test func cycleDayCountIsTheDaysFromTheCycleStartToTheReset() {
  #expect(Runway.cycleDayCount(resetDate: utcDate("2026-11-01T00:00:00Z")) == 31)
  #expect(Runway.cycleDayCount(resetDate: utcDate("2026-10-01T00:00:00Z")) == 30)
  #expect(Runway.cycleDayCount(resetDate: utcDate("2026-03-01T00:00:00Z")) == 28)
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

@Test func lastCycleDayIsTheDayBeforeReset() {
  #expect(Runway.lastCycleDay(resetDate: utcDate("2026-11-01T00:00:00Z")) == utcDate("2026-10-31T00:00:00Z"))
}

@Test func lastsTheCycleFalseWhenRunOutBeforeReset() {
  // 600/day, 6000 left -> runs out Oct 21.
  #expect(!Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-11T00:00:00Z")))
}

@Test func lastsTheCycleTrueWhenRunOutEqualsReset() {
  // 100/day, 2100 left -> runs out exactly Nov 1.
  #expect(Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 1000, entitlement: 3100), now: utcDate("2026-10-11T00:00:00Z")))
}

@Test func lastsTheCycleTrueWhenRunOutAfterReset() {
  #expect(Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-10-11T00:00:00Z")))
}

@Test func lastsTheCycleFalseWithoutBurnUnlimitedOrStale() {
  let now = utcDate("2026-10-11T00:00:00Z")
  #expect(!Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 0), now: now))
  #expect(!Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true), now: now))
  #expect(!Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-11-01T00:00:00Z")))
}

@Test func workdayAverageCountsOnlyWorkdays() {
  let usage = makeUsage(creditsUsed: 7000)
  let now = utcDate("2026-10-11T00:00:00Z")
  #expect(Runway.averageDailyBurn(usage: usage, now: now, days: utcWorkdays) == 1000)
  #expect(Runway.wholeDaysLeft(usage: usage, now: now, days: utcWorkdays) == 5)
  // 5 workdays from Monday Oct 12 end on Friday Oct 16 at midnight.
  #expect(Runway.runOutDate(usage: usage, now: now, days: utcWorkdays) == utcDate("2026-10-17T00:00:00Z"))
  #expect(abs(Runway.dailyHeadroom(usage: usage, now: now, days: utcWorkdays)! - (5000.0 / 15 - 1000)) < 1e-9)
}

@Test func workdayAverageHoldsOverTheWeekend() {
  let usage = makeUsage(creditsUsed: 7000)
  #expect(Runway.averageDailyBurn(usage: usage, now: utcDate("2026-10-10T00:00:00Z"), days: utcWorkdays)
    == Runway.averageDailyBurn(usage: usage, now: utcDate("2026-10-11T23:00:00Z"), days: utcWorkdays))
}

@Test func headroomIsNilWhenOnlyAWeekendIsLeft() {
  #expect(Runway.dailyHeadroom(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-31T00:00:00Z"), days: utcWorkdays) == nil)
}

@Test func workdayAverageCountsAtLeastOneWorkday() {
  // The Aug 1 2026 cycle starts on a Saturday, so no workday has passed by Sunday noon.
  let usage = makeUsage(creditsUsed: 300, resetDate: utcDate("2026-09-01T00:00:00Z"))
  #expect(Runway.averageDailyBurn(usage: usage, now: utcDate("2026-08-02T12:00:00Z"), days: utcWorkdays) == 300)
}
