import Core
import Foundation
import Testing

// makeUsage resets at 2026-11-01 with 12000 credits, so 80% is 9600.

func runwayNotices(usage: CopilotUsage?, now: String, sentKeys: Set<String> = []) -> [RunwayNotice] {
  RunwayNotice.toSend(usage: usage, now: utcDate(now), sentKeys: sentKeys, locale: usLocale)
}

@Test func used80FiresWhileHealthIsHealthy() {
  // 28 days in, 9600 used: 7 days left, run-out after the reset.
  let usage = makeUsage(creditsUsed: 9600)
  #expect(RunwayHealth(usage: usage, now: utcDate("2026-10-29T00:00:00Z")) == .healthy)
  #expect(runwayNotices(usage: usage, now: "2026-10-29T00:00:00Z") == [
    RunwayNotice(
      kind: .used80,
      key: "used80-2026-11-01",
      title: "80% of credits used",
      body: "At this pace your credits last past the reset on Nov 1."
    ),
  ])
}

@Test func shortNoticeNamesDaysLeft() {
  // 10 days in, 6000 used: 10 days left, run-out 2026-10-21.
  #expect(runwayNotices(usage: makeUsage(creditsUsed: 6000), now: "2026-10-11T00:00:00Z") == [
    RunwayNotice(
      kind: .short,
      key: "short-2026-11-01",
      title: "Runway is short: 10 days left",
      body: "At this pace you run out on Oct 21, 11 days before the reset on Nov 1."
    ),
  ])
}

@Test func shortNoticeUsesSingularDayAfterUsed80() {
  // 20 days in, 11000 used: 1.8 days left.
  let sentNotices = runwayNotices(usage: makeUsage(creditsUsed: 11000), now: "2026-10-21T00:00:00Z")
  #expect(sentNotices.map(\.kind) == [.used80, .short])
  #expect(sentNotices.last?.title == "Runway is short: 1 day left")
}

@Test func criticalNoticeFiresWhileCreditsRemain() {
  // 20 days in, 11800 used: 200 left, under 1 day.
  let sentNotices = runwayNotices(usage: makeUsage(creditsUsed: 11800), now: "2026-10-21T00:00:00Z")
  #expect(sentNotices.map(\.kind) == [.used80, .critical])
  #expect(sentNotices.last == RunwayNotice(
    kind: .critical,
    key: "critical-2026-11-01",
    title: "Runway is critical: under 1 day left",
    body: "At this pace you run out on Oct 21, 11 days before the reset on Nov 1."
  ))
}

@Test func limitReachedReplacesCritical() {
  for creditsUsed in [12000.0, 12500.0] {
    let usage = makeUsage(creditsUsed: creditsUsed)
    #expect(RunwayHealth(usage: usage, now: utcDate("2026-10-21T00:00:00Z")) == .critical)
    let sentNotices = runwayNotices(usage: usage, now: "2026-10-21T00:00:00Z")
    #expect(sentNotices.map(\.kind) == [.used80, .limitReached])
    #expect(sentNotices.last == RunwayNotice(
      kind: .limitReached,
      key: "limitReached-2026-11-01",
      title: "Credit limit reached",
      body: "You used all credits for this cycle. Resets Nov 1."
    ))
  }
}

@Test func eachNoticeFiresOncePerCycle() {
  let cases: [(creditsUsed: Double, now: String)] = [
    (9600, "2026-10-29T00:00:00Z"),
    (6000, "2026-10-11T00:00:00Z"),
    (11800, "2026-10-21T00:00:00Z"),
    (12500, "2026-10-21T00:00:00Z"),
  ]
  var sentKeys: Set<String> = []
  var sentKinds: [RunwayNotice.Kind] = []
  for (creditsUsed, now) in cases {
    let usage = makeUsage(creditsUsed: creditsUsed)
    let firstNotices = runwayNotices(usage: usage, now: now, sentKeys: sentKeys)
    sentKeys.formUnion(firstNotices.map(\.key))
    sentKinds += firstNotices.map(\.kind)
    #expect(runwayNotices(usage: usage, now: now, sentKeys: sentKeys).isEmpty)
  }
  #expect(sentKinds == [.used80, .short, .critical, .limitReached])
}

@Test func sentKeyDoesNotFireAgain() {
  let sentKeys: Set<String> = ["used80-2026-11-01"]
  let sentNotices = runwayNotices(usage: makeUsage(creditsUsed: 11000), now: "2026-10-21T00:00:00Z", sentKeys: sentKeys)
  #expect(sentNotices.map(\.kind) == [.short])
}

@Test func newResetDateFiresAgain() {
  let lastCycleKeys = Set(runwayNotices(usage: makeUsage(creditsUsed: 9600), now: "2026-10-29T00:00:00Z").map(\.key))
  #expect(lastCycleKeys == ["used80-2026-11-01"])
  let nextCycleUsage = CopilotUsage(
    creditsUsed: 9600,
    entitlement: 12000,
    creditsRemaining: 2400,
    percentRemaining: 20,
    isUnlimited: false,
    resetDate: utcDate("2026-12-01T00:00:00Z")
  )
  let sentNotices = runwayNotices(usage: nextCycleUsage, now: "2026-11-29T00:00:00Z", sentKeys: lastCycleKeys)
  #expect(sentNotices.map(\.key) == ["used80-2026-12-01"])
}

@Test func unlimitedMissingOrPastUsageGivesNoNotice() {
  #expect(runwayNotices(usage: makeUsage(creditsUsed: 12500, entitlement: 0, isUnlimited: true), now: "2026-10-21T00:00:00Z").isEmpty)
  #expect(runwayNotices(usage: nil, now: "2026-10-21T00:00:00Z").isEmpty)
  #expect(runwayNotices(usage: makeUsage(creditsUsed: 12500), now: "2026-11-02T00:00:00Z").isEmpty)
}

@Test func noticeKeysAreStableStrings() {
  let resetDate = utcDate("2026-11-01T00:00:00Z")
  #expect(RunwayNotice.Kind.allCases.map { RunwayNotice.key(kind: $0, resetDate: resetDate) } == [
    "used80-2026-11-01",
    "short-2026-11-01",
    "critical-2026-11-01",
    "limitReached-2026-11-01",
  ])
}

@Test func limitSentenceNamesResetDay() {
  let usage = makeUsage(creditsUsed: 12500)
  #expect(RunwayInsight.limitSentence(usage: usage, locale: usLocale) == "You used all credits for this cycle. Resets Nov 1.")
  #expect(
    RunwayInsight.limitSentence(usage: usage, locale: Locale(identifier: "en_GB"))
      == "You used all credits for this cycle. Resets 1 Nov."
  )
}
