import Core
import Foundation
import Testing

// makeUsage resets at 2026-11-01, so the cycle starts 2026-10-01.

@Test func runwayPastResetIsHealthy() {
  // 10 days in, 1000 used: 110 days left, run-out after the reset.
  #expect(RunwayHealth(usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-10-11T00:00:00Z")) == .healthy)
}

@Test func runOutBeforeResetIsShort() {
  // 10 days in, 6000 used: 10 days left, run-out 2026-10-21.
  #expect(RunwayHealth(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-11T00:00:00Z")) == .short)
}

@Test func runOutExactlyAtResetIsHealthy() {
  // 10 days in, 1000 of 3100 used: burn 100/day, 2100 left -> 21 days, run-out 2026-11-01.
  let usage = makeUsage(creditsUsed: 1000, entitlement: 3100)
  let now = utcDate("2026-10-11T00:00:00Z")
  #expect(Runway.runOutDate(usage: usage, now: now) == usage.resetDate)
  #expect(RunwayHealth(usage: usage, now: now) == .healthy)
}

@Test func underOneDayLeftIsCritical() {
  // 10 days in, 11000 used: burn 1100/day, 1000 left -> 0.91 days.
  #expect(RunwayHealth(usage: makeUsage(creditsUsed: 11000), now: utcDate("2026-10-11T00:00:00Z")) == .critical)
}

@Test func exactlyOneDayLeftIsShortNotCritical() {
  // 11 days in, 11000 used: burn 1000/day, 1000 left -> exactly 1 day.
  let usage = makeUsage(creditsUsed: 11000)
  let now = utcDate("2026-10-12T00:00:00Z")
  #expect(Runway.daysLeft(usage: usage, now: now) == 1)
  #expect(RunwayHealth(usage: usage, now: now) == .short)
}

@Test func noCreditsLeftIsCritical() {
  #expect(RunwayHealth(usage: makeUsage(creditsUsed: 12000), now: utcDate("2026-10-11T00:00:00Z")) == .critical)
}

@Test func criticalWinsWhenResetIsAlsoClose() {
  // 30.5 days in, 11900 used: under one day left and the reset is 12 hours away.
  #expect(RunwayHealth(usage: makeUsage(creditsUsed: 11900), now: utcDate("2026-10-31T12:00:00Z")) == .critical)
}

@Test func noBurnYetIsHealthy() {
  #expect(RunwayHealth(usage: makeUsage(creditsUsed: 0), now: utcDate("2026-10-11T00:00:00Z")) == .healthy)
}

@Test func unlimitedPlanIsHealthy() {
  let usage = makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true)
  #expect(RunwayHealth(usage: usage, now: utcDate("2026-10-11T00:00:00Z")) == .healthy)
}

@Test func missingUsageIsUnavailable() {
  #expect(RunwayHealth(usage: nil, hasError: false, now: utcDate("2026-10-11T00:00:00Z")) == .unavailable)
}

@Test func errorMakesStaleUsageUnavailable() {
  let usage = makeUsage(creditsUsed: 1000)
  let now = utcDate("2026-10-11T00:00:00Z")
  #expect(RunwayHealth(usage: usage, hasError: true, now: now) == .unavailable)
  #expect(RunwayHealth(usage: usage, hasError: false, now: now) == .healthy)
}

// Fri 2027-01-29 noon, reset Mon 2027-02-01. 290 of 300 used: under 1 day left either way, but in
// workdays the weekend pushes the run-out to the reset or later.
private let fridayBeforeReset = utcDate("2027-01-29T12:00:00Z")
private let mondayReset = utcDate("2027-02-01T00:00:00Z")

@Test func workdayRunOutAtOrAfterResetIsHealthyEvenUnderOneWorkday() {
  let usage = makeUsage(creditsUsed: 290, entitlement: 300, resetDate: mondayReset)
  #expect(RunwayHealth(usage: usage, now: fridayBeforeReset, days: utcWorkdays) == .healthy)
  #expect(RunwayHealth(usage: usage, now: fridayBeforeReset, days: .calendar) == .critical)
}

@Test func daysReachesRunwayHealth() {
  // 285 of 300 used: calendar has 1.5 days left and runs out Sun 2027-01-31 (short).
  // Workdays skip the weekend, so the run-out lands on Mon 2027-02-01 or later (healthy).
  let usage = makeUsage(creditsUsed: 285, entitlement: 300, resetDate: mondayReset)
  #expect(RunwayHealth(usage: usage, now: fridayBeforeReset, days: .calendar) == .short)
  #expect(RunwayHealth(usage: usage, now: fridayBeforeReset, days: utcWorkdays) == .healthy)
}
