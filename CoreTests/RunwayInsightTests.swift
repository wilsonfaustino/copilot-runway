import Core
import Foundation
import Testing

// makeUsage resets at 2026-11-01, so the cycle starts 2026-10-01.

let usLocale = Locale(identifier: "en_US")

@Test func shortRunwayNamesRunOutAndDaysBeforeReset() {
  // 10 days in, 6000 used: 10 days left, run-out 2026-10-21.
  let sentence = RunwayInsight.runOutSentence(
    usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale
  )
  #expect(sentence == "At this pace you run out on Oct 21, 11 days before the reset on Nov 1.")
}

@Test func runOutOneDayBeforeResetUsesSingularDay() {
  // 10 days in, 4000 used: 20 days left, run-out 2026-10-31.
  let sentence = RunwayInsight.runOutSentence(
    usage: makeUsage(creditsUsed: 4000), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale
  )
  #expect(sentence == "At this pace you run out on Oct 31, 1 day before the reset on Nov 1.")
}

@Test func healthyRunwayLastsPastReset() {
  let sentence = RunwayInsight.runOutSentence(
    usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale
  )
  #expect(sentence == "At this pace your credits last past the reset on Nov 1.")
}

@Test func noBurnHasNoSentence() {
  #expect(RunwayInsight.runOutSentence(usage: makeUsage(creditsUsed: 0), now: utcDate("2026-10-11T00:00:00Z")) == nil)
}

@Test func unlimitedPlanHasNoSentenceOrRequiredBurn() {
  let usage = makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true)
  let now = utcDate("2026-10-11T00:00:00Z")
  #expect(RunwayInsight.runOutSentence(usage: usage, now: now) == nil)
  #expect(RunwayInsight.requiredDailyBurn(usage: usage, now: now) == nil)
}

@Test func passedResetHasNoSentenceOrRequiredBurn() {
  let usage = makeUsage(creditsUsed: 6000)
  let now = utcDate("2026-11-02T00:00:00Z")
  #expect(RunwayInsight.runOutSentence(usage: usage, now: now) == nil)
  #expect(RunwayInsight.requiredDailyBurn(usage: usage, now: now) == nil)
}

@Test func sentenceDatesFollowLocale() {
  let sentence = RunwayInsight.runOutSentence(
    usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-10-11T00:00:00Z"), locale: Locale(identifier: "en_GB")
  )
  #expect(sentence == "At this pace your credits last past the reset on 1 Nov.")
}

@Test func requiredBurnSpreadsRemainingOverDaysUntilReset() {
  // 11 days until the reset, 5500 credits left.
  let usage = makeUsage(creditsUsed: 6500)
  #expect(RunwayInsight.requiredDailyBurn(usage: usage, now: utcDate("2026-10-21T00:00:00Z")) == 500)
}

@Test func requiredBurnIsZeroWithNoCreditsLeft() {
  let usage = makeUsage(creditsUsed: 12500)
  #expect(RunwayInsight.requiredDailyBurn(usage: usage, now: utcDate("2026-10-21T00:00:00Z")) == 0)
}

@Test func overageRunOutIsNotInThePast() {
  // 20 days in, 12500 of 12000 used: the estimated run-out is 2026-10-20, a day before now.
  let sentence = RunwayInsight.runOutSentence(
    usage: makeUsage(creditsUsed: 12500), now: utcDate("2026-10-21T00:00:00Z"), locale: usLocale
  )
  #expect(sentence == "At this pace you run out on Oct 21, 11 days before the reset on Nov 1.")
}

@Test func gapIsTheShareOfGitHubCreditsNotInLocalSessions() {
  #expect(RunwayInsight.percentNotInLocalSessions(creditsUsed: 8857, localCredits: 7703) == 13)
}

@Test func gapIsHiddenWhenItIsNotMeaningful() {
  #expect(RunwayInsight.percentNotInLocalSessions(creditsUsed: 0, localCredits: 0) == nil)
  #expect(RunwayInsight.percentNotInLocalSessions(creditsUsed: 1000, localCredits: 1200) == nil)
  #expect(RunwayInsight.percentNotInLocalSessions(creditsUsed: 1000, localCredits: 1000) == nil)
  // 0.4% rounds to 0%.
  #expect(RunwayInsight.percentNotInLocalSessions(creditsUsed: 1000, localCredits: 996) == nil)
}

@Test func topCategoryShareIsTheLargestCategory() {
  let categoryCredits = [
    CategoryCredits(category: .investigation, credits: 420),
    CategoryCredits(category: .implementation, credits: 380),
    CategoryCredits(category: .review, credits: 200),
  ]
  let topShare = RunwayInsight.topCategoryShare(categoryCredits: categoryCredits)
  #expect(topShare?.category == .investigation)
  #expect(topShare?.percent == 42)
}

@Test func topCategoryShareNeedsCredits() {
  #expect(RunwayInsight.topCategoryShare(categoryCredits: []) == nil)
  #expect(RunwayInsight.topCategoryShare(categoryCredits: [CategoryCredits(category: .review, credits: 0)]) == nil)
}
