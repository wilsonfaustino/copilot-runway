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

// Banner and popover sentences. makeUsage has 12000 credits, so 6000 used 10 days in runs out on 2026-10-21.

@Test func bannerShowsErrorFirst() {
  let banner = RunwayInsight.banner(
    usage: makeUsage(creditsUsed: 6000), errorMessage: "Offline.", categoryCredits: [],
    now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale
  )
  #expect(banner.headline == "Offline.")
  #expect(banner.detail == "The numbers below are from the last good refresh.")
}

@Test func bannerForUnlimitedPlanShowsCreditsUsed() {
  let banner = RunwayInsight.banner(
    usage: makeUsage(creditsUsed: 1500, entitlement: 0, isUnlimited: true), errorMessage: nil, categoryCredits: [],
    now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale
  )
  #expect(banner.headline == "Unlimited plan.")
  #expect(banner.detail == "1,500 credits used this cycle.")
}

@Test func bannerForShortRunwayAddsTargetBurnAndTopCategory() {
  let categoryCredits = [
    CategoryCredits(category: .investigation, credits: 420),
    CategoryCredits(category: .implementation, credits: 580),
  ]
  // 6000 credits left over 21 days is 285.7 a day, rounded down to 285.
  let banner = RunwayInsight.banner(
    usage: makeUsage(creditsUsed: 6000), errorMessage: nil, categoryCredits: categoryCredits,
    now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale
  )
  #expect(banner.headline == "At this pace you run out on Oct 21, 11 days before the reset on Nov 1.")
  #expect(banner.detail == "To reach Nov 1, keep the burn under 285 credits/day. 314 credits/day over budget. Implementation turns use 58% of local credits.")
}

@Test func bannerForHealthyRunwayHasNoTargetBurnButHeadroom() {
  let banner = RunwayInsight.banner(
    usage: makeUsage(creditsUsed: 1000), errorMessage: nil, categoryCredits: [],
    now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale
  )
  #expect(banner.headline == "At this pace your credits last past the reset on Nov 1.")
  #expect(banner.detail == "424 credits/day of headroom.")
}

@Test func bannerInOverageHasNoTargetBurn() {
  // No credits are left, so the target burn is 0 and the banner gives no target.
  let banner = RunwayInsight.banner(
    usage: makeUsage(creditsUsed: 12500), errorMessage: nil, categoryCredits: [],
    now: utcDate("2026-10-21T00:00:00Z"), locale: usLocale
  )
  #expect(banner.headline == "At this pace you run out on Oct 21, 11 days before the reset on Nov 1.")
  #expect(banner.detail == "")
}

@Test func bannerWithNoBurnShowsResetDate() {
  let banner = RunwayInsight.banner(
    usage: makeUsage(creditsUsed: 0), errorMessage: nil,
    categoryCredits: [CategoryCredits(category: .review, credits: 10)],
    now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale
  )
  #expect(banner.headline == "No credits used yet this cycle.")
  #expect(banner.detail == "Resets Nov 1. Review turns use 100% of local credits.")
}

@Test func bannerAfterResetFallsBackToResetDate() {
  let banner = RunwayInsight.banner(
    usage: makeUsage(creditsUsed: 6000), errorMessage: nil, categoryCredits: [],
    now: utcDate("2026-11-02T00:00:00Z"), locale: usLocale
  )
  #expect(banner.headline == "No credits used yet this cycle.")
  #expect(banner.detail == "Resets Nov 1.")
}

@Test func popoverSentenceShowsRunOut() {
  let sentence = RunwayInsight.popoverSentence(
    usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale
  )
  #expect(sentence == "Runs out Oct 21, 11 days early.\n314 credits/day over budget.")
}

@Test func popoverSentenceRunOutOneDayBeforeResetUsesSingularDay() {
  let sentence = RunwayInsight.popoverSentence(
    usage: makeUsage(creditsUsed: 4000), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale
  )
  #expect(sentence == "Runs out Oct 31, 1 day early.\n19 credits/day over budget.")
}

@Test func popoverSentenceForHealthyRunway() {
  let sentence = RunwayInsight.popoverSentence(
    usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale
  )
  #expect(sentence == "Lasts past the Nov 1 reset.\n424 credits/day of headroom.")
}

@Test func popoverSentenceDatesFollowLocale() {
  let sentence = RunwayInsight.popoverSentence(
    usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-10-11T00:00:00Z"), locale: Locale(identifier: "en_GB")
  )
  #expect(sentence == "Lasts past the 1 Nov reset.\n424 credits/day of headroom.")
}

@Test func popoverSentenceForUnlimitedPlan() {
  let usage = makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true)
  #expect(RunwayInsight.popoverSentence(usage: usage, now: utcDate("2026-10-11T00:00:00Z")) == "Unlimited plan, no run-out.")
}

@Test func popoverSentenceWithNoBurn() {
  let usage = makeUsage(creditsUsed: 0)
  #expect(RunwayInsight.popoverSentence(usage: usage, now: utcDate("2026-10-11T00:00:00Z")) == "No credits used yet.")
}

@Test func popoverSentenceAfterResetIsNil() {
  #expect(RunwayInsight.popoverSentence(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-11-02T00:00:00Z")) == nil)
}

// 360 pt popover, 16 pt padding, 116 pt ring and 18 pt gap leave 194 pt. At 12.5 pt that is about 30 characters.
@Test func popoverSentenceLinesFitNextToTheRing() {
  let now = utcDate("2026-10-11T00:00:00Z")
  let usages = [
    makeUsage(creditsUsed: 6000), makeUsage(creditsUsed: 4000), makeUsage(creditsUsed: 1000), makeUsage(creditsUsed: 0),
    makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true),
  ]
  for usage in usages {
    let lines = RunwayInsight.popoverSentence(usage: usage, now: now, locale: usLocale)?.split(separator: "\n") ?? []
    #expect(lines.count <= 2)
    #expect(lines.allSatisfy { $0.count <= 31 })
  }
}

@Test func headroomTextIsNilWithoutALimit() {
  let usage = makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true)
  #expect(RunwayInsight.headroomText(usage: usage, now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale) == nil)
}

@Test func headroomTextIsNilWithoutUsage() {
  #expect(RunwayInsight.headroomText(usage: makeUsage(creditsUsed: 0), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale) == nil)
}

@Test func headroomTextIsNilWhenAlreadyOver() {
  #expect(RunwayInsight.headroomText(usage: makeUsage(creditsUsed: 12000), now: utcDate("2026-10-21T00:00:00Z"), locale: usLocale) == nil)
  #expect(RunwayInsight.headroomText(usage: makeUsage(creditsUsed: 12500), now: utcDate("2026-10-21T00:00:00Z"), locale: usLocale) == nil)
}

@Test func headroomTextIsNilAfterTheReset() {
  #expect(RunwayInsight.headroomText(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-11-02T00:00:00Z"), locale: usLocale) == nil)
}

@Test func headroomTextIsPositiveBelowTheAllowedBurn() {
  // 11,000 left over 21 days is 523.8 a day. The average burn is 1,000 over 10 days, 100 a day.
  let text = RunwayInsight.headroomText(usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale)
  #expect(text == "424 credits/day of headroom")
}

@Test func headroomTextIsNegativeAboveTheAllowedBurn() {
  // 6,000 left over 21 days is 285.7 a day. The average burn is 6,000 over 10 days, 600 a day.
  let text = RunwayInsight.headroomText(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale)
  #expect(text == "314 credits/day over budget")
}

@Test func headroomOnResetDayUsesTheRealDaysUntilTheReset() {
  // 6,000 left over the 0.5 days to the reset is 12,000 a day. The average burn is 6,000 over 30.5 days, 196.7 a day.
  let usage = makeUsage(creditsUsed: 6000)
  let now = utcDate("2026-10-31T12:00:00Z")
  #expect(Runway.allowedDailyBurn(usage: usage, now: now) == 12000)
  #expect(RunwayInsight.headroomText(usage: usage, now: now, locale: usLocale) == "11,803 credits/day of headroom")
}

@Test func headroomOnResetDayIsPositiveWhenRunOutFallsAfterTheReset() throws {
  // 200 left, burn 300 a day, 0.5 days to the reset: the allowance is 400 a day, so 100 a day of headroom.
  let usage = makeUsage(creditsUsed: 9150, entitlement: 9350)
  let now = utcDate("2026-10-31T12:00:00Z")
  let headroom = try #require(Runway.dailyHeadroom(usage: usage, now: now))
  #expect(abs(headroom - 100) < 0.0001)
  #expect(RunwayInsight.headroomText(usage: usage, now: now, locale: usLocale) == "100 credits/day of headroom")
}

@Test func headroomOnResetDayIsNegativeWhenRunOutFallsBeforeTheReset() throws {
  // 100 left, burn 300 a day, 0.5 days to the reset: the allowance is 200 a day, so 100 a day over budget.
  let usage = makeUsage(creditsUsed: 9150, entitlement: 9250)
  let now = utcDate("2026-10-31T12:00:00Z")
  let headroom = try #require(Runway.dailyHeadroom(usage: usage, now: now))
  #expect(abs(headroom + 100) < 0.0001)
  #expect(RunwayInsight.headroomText(usage: usage, now: now, locale: usLocale) == "100 credits/day over budget")
}

@Test func headroomSignAgreesWithRunOutDateAgainstTheReset() throws {
  let nowValues = ["2026-10-02T06:00:00Z", "2026-10-11T00:00:00Z", "2026-10-25T18:00:00Z", "2026-10-31T12:00:00Z", "2026-10-31T23:00:00Z"]
  for creditsUsed in [100.0, 3000, 6000, 9000, 11_000, 11_900] {
    for nowValue in nowValues {
      let usage = makeUsage(creditsUsed: creditsUsed)
      let now = utcDate(nowValue)
      let headroom = try #require(Runway.dailyHeadroom(usage: usage, now: now))
      let runOutDate = try #require(Runway.runOutDate(usage: usage, now: now))
      #expect((headroom > 0) == (runOutDate > usage.resetDate), "used \(creditsUsed) at \(nowValue)")
    }
  }
}

@Test func headroomIsNilAtTheExactReset() {
  let usage = makeUsage(creditsUsed: 6000)
  #expect(Runway.dailyHeadroom(usage: usage, now: usage.resetDate) == nil)
  #expect(RunwayInsight.headroomText(usage: usage, now: usage.resetDate, locale: usLocale) == nil)
}
