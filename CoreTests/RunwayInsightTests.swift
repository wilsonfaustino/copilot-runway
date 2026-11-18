@testable import Core
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
  // The figure and caption already say the credits last the cycle, so only the headroom line is left.
  #expect(sentence == "424 credits/day of headroom.")
}

@Test func popoverSentenceDatesFollowLocale() {
  let sentence = RunwayInsight.popoverSentence(
    usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-11T00:00:00Z"), locale: Locale(identifier: "en_GB")
  )
  #expect(sentence?.hasPrefix("Runs out 21 Oct, 11 days early.") == true)
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

@Test func resetCaptionShowsUTCResetDay() {
  #expect(RunwayInsight.resetCaption(usage: makeUsage(creditsUsed: 1000), locale: Locale(identifier: "en_US")) == "Resets Nov 1")
}

@Test func headroomTextUsesWorkdays() {
  let text = RunwayInsight.headroomText(usage: makeUsage(creditsUsed: 7000), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale, days: utcWorkdays)
  #expect(text == "667 credits/workday over budget")
}

@Test func bannerTargetUsesWorkdays() {
  let banner = RunwayInsight.banner(usage: makeUsage(creditsUsed: 7000), errorMessage: nil, categoryCredits: [], now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale, days: utcWorkdays)
  #expect(banner.detail.hasPrefix("To reach Nov 1, keep the burn under 333 credits/workday. 667 credits/workday over budget."))
}

@Test func runOutSentenceCountsWorkdaysBeforeResetInWorkdayMode() {
  // The run-out is Sat Oct 17 00:00, and the gap to Nov 1 has 10 workdays.
  let sentence = RunwayInsight.runOutSentence(
    usage: makeUsage(creditsUsed: 7000), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale, days: utcWorkdays
  )
  #expect(sentence == "At this pace you run out on Oct 17, 10 workdays before the reset on Nov 1.")
}

// The cycle resets Tue Dec 1. On Mon Nov 16 10 workdays have passed, so the burn is creditsUsed / 10 per workday.
private let workdayGapReset = utcDate("2026-12-01T00:00:00Z")
private let workdayGapNow = utcDate("2026-11-16T00:00:00Z")

@Test func popoverCountsWorkdaysEarlyInWorkdayMode() {
  // 850 left at 100/workday: 8.5 workdays, run-out Thu Nov 26. Nov 26, 27 and 30 are workdays.
  let usage = makeUsage(creditsUsed: 1000, entitlement: 1850, resetDate: workdayGapReset)
  let sentence = RunwayInsight.popoverSentence(usage: usage, now: workdayGapNow, locale: usLocale, days: utcWorkdays)
  #expect(sentence?.hasPrefix("Runs out Nov 26, 3 workdays early.\n") == true)
  #expect(
    RunwayInsight.runOutSentence(usage: usage, now: workdayGapNow, locale: usLocale, days: utcWorkdays)
      == "At this pace you run out on Nov 26, 3 workdays before the reset on Dec 1.")
}

@Test func workdaysEarlySkipsDaysOff() {
  let usage = makeUsage(creditsUsed: 1000, entitlement: 1850, resetDate: workdayGapReset)
  let days = RunwayDays.workdays(TimeZone(identifier: "UTC")!, daysOff: [LocalDay(string: "2026-11-27")!])
  let sentence = RunwayInsight.popoverSentence(usage: usage, now: workdayGapNow, locale: usLocale, days: days)
  #expect(sentence?.hasPrefix("Runs out Nov 26, 2 workdays early.\n") == true)
}

@Test func oneWorkdayEarlyUsesSingularWorkday() {
  // 1050 left at 100/workday: 10.5 workdays, run-out Mon Nov 30.
  let usage = makeUsage(creditsUsed: 1000, entitlement: 2050, resetDate: workdayGapReset)
  let sentence = RunwayInsight.popoverSentence(usage: usage, now: workdayGapNow, locale: usLocale, days: utcWorkdays)
  #expect(sentence?.hasPrefix("Runs out Nov 30, 1 workday early.\n") == true)
}

@Test func overageCountsWorkdaysFromToday() {
  let usage = makeUsage(creditsUsed: 13000, resetDate: workdayGapReset)
  let now = utcDate("2026-11-26T12:00:00Z")
  #expect(
    RunwayInsight.runOutSentence(usage: usage, now: now, locale: usLocale, days: utcWorkdays)
      == "At this pace you run out on Nov 26, 3 workdays before the reset on Dec 1.")
}

// Nov 30 00:30 UTC is still Sun Nov 29 in Los Angeles. The gap uses the UTC date, so Mon Nov 30 counts.
@Test func workdayGapUsesTheUTCDateInAnyTimeZone() {
  let usage = makeUsage(creditsUsed: 13000, resetDate: workdayGapReset)
  let days = RunwayDays.workdays(TimeZone(identifier: "America/Los_Angeles")!)
  #expect(
    RunwayInsight.runOutSentence(usage: usage, now: utcDate("2026-11-30T00:30:00Z"), locale: usLocale, days: days)
      == "At this pace you run out on Nov 30, 1 workday before the reset on Dec 1.")
}

// Overage on Sat Jan 30 2027 with the reset on Mon Feb 1: no workday is left, so the text has no count.
@Test func noWorkdayLeftBeforeResetDropsTheCount() {
  let usage = makeUsage(creditsUsed: 13000, resetDate: utcDate("2027-02-01T00:00:00Z"))
  let now = utcDate("2027-01-30T12:00:00Z")
  #expect(
    RunwayInsight.popoverSentence(usage: usage, now: now, locale: usLocale, days: utcWorkdays)
      == "Runs out Jan 30, before the reset.")
  #expect(
    RunwayInsight.runOutSentence(usage: usage, now: now, locale: usLocale, days: utcWorkdays)
      == "At this pace you run out on Jan 30, before the reset on Feb 1.")
}

private let combinedInsightReset = utcDate("2026-12-01T00:00:00Z")
private let combinedInsightNow = utcDate("2026-11-15T12:00:00Z")

private func combinedInsightBudget(copilotUsed: Double = 10216, portkeySpent: Double = 9.26) throws -> CombinedBudget {
  let copilot = QuotaUsage(
    creditsUsed: copilotUsed, entitlement: 15000, creditsRemaining: 15000 - copilotUsed, percentRemaining: 31.8933,
    isUnlimited: false, resetDate: combinedInsightReset)
  return try #require(CombinedBudget.make(copilot: copilot, portkeySpentUSD: portkeySpent, portkeyBudgetUSD: 50))
}

@Test func combinedHeadroomInUSD() throws {
  let combined = try combinedInsightBudget()
  let text = RunwayInsight.headroomText(usage: combined.usage, now: combinedInsightNow, locale: usLocale, unit: .usd)
  #expect(text == "$1.97/day over budget")
}

@Test func combinedHeadroomFollowsLocale() throws {
  let combined = try combinedInsightBudget()
  let text = try #require(
    RunwayInsight.headroomText(
      usage: combined.usage, now: combinedInsightNow, locale: Locale(identifier: "pt_BR"), unit: .usd))
  #expect(text == "$1,97/day over budget")
  #expect(!text.contains("credits"))
}

@Test func combinedPopoverSentenceUsesUSD() throws {
  let combined = try combinedInsightBudget()
  let sentence = try #require(
    RunwayInsight.popoverSentence(usage: combined.usage, now: combinedInsightNow, locale: usLocale, unit: .usd))
  #expect(sentence.hasSuffix("\n$1.97/day over budget."))
}

@Test func combinedNothingSpent() throws {
  let combined = try combinedInsightBudget(copilotUsed: 0, portkeySpent: 0)
  #expect(
    RunwayInsight.popoverSentence(usage: combined.usage, now: combinedInsightNow, locale: usLocale, unit: .usd)
      == "Nothing spent yet.")
}

@Test func combinedBannerUsesUSDAndNamesEachProviderAverage() throws {
  let combined = try combinedInsightBudget()
  let banner = RunwayInsight.banner(
    usage: makeUsage(creditsUsed: 10216), errorMessage: nil, categoryCredits: [], now: combinedInsightNow,
    locale: usLocale, combined: combined)
  // 88.58 USD left at 7.68 USD/day: 11.5 days, run-out Nov 27. Needed: 88.58 / 15.5 days = 5.71 USD/day.
  #expect(banner.headline == "At this pace you run out on Nov 27, 4 days before the reset on Dec 1.")
  #expect(
    banner.detail
      == "To reach Dec 1, keep the burn under $5.71/day. $1.97/day over budget. "
      + "Copilot averages $7.05/day and Portkey $0.64/day.")
}

@Test func combinedBannerWithNothingSpent() throws {
  let combined = try combinedInsightBudget(copilotUsed: 0, portkeySpent: 0)
  let banner = RunwayInsight.banner(
    usage: makeUsage(creditsUsed: 0), errorMessage: nil, categoryCredits: [], now: combinedInsightNow,
    locale: usLocale, combined: combined)
  #expect(banner.headline == "Nothing spent yet this cycle.")
  #expect(banner.detail == "Resets Dec 1.")
}

// Copilot alone runs short ($20 of $150 left), but an unused $150 Portkey budget makes the combined budget last.
@Test func combinedBannerThatLastsNamesTheCombinedBudget() throws {
  let copilot = QuotaUsage(
    creditsUsed: 13000, entitlement: 15000, creditsRemaining: 2000, percentRemaining: 13.3333,
    isUnlimited: false, resetDate: combinedInsightReset)
  let combined = try #require(CombinedBudget.make(copilot: copilot, portkeySpentUSD: 0, portkeyBudgetUSD: 150))
  let banner = RunwayInsight.banner(
    usage: copilot, errorMessage: nil, categoryCredits: [], now: combinedInsightNow, locale: usLocale, combined: combined)
  #expect(banner.headline == "At this pace your combined budget lasts past the reset on Dec 1.")
}

@Test func portkeyOnlyBannerNoBudget() {
  let banner = RunwayInsight.portkeyOnlyBanner(
    usage: nil, spentUSD: 10.17, absence: .notLoggedIn, now: utcDate("2026-11-16T00:00:00Z"), locale: usLocale)
  #expect(banner.headline == "$10.17 spent on Portkey this month.")
  #expect(banner.detail == PortkeyOnly.causeLine(.notLoggedIn, hasBudget: false))
}

@Test func portkeyOnlyBannerRunsOut() {
  let now = utcDate("2026-11-16T00:00:00Z")
  let usage = PortkeyBudget.usage(spentUSD: 9, budgetUSD: 12, resetDate: utcDate("2026-12-01T00:00:00Z"))!
  let banner = RunwayInsight.portkeyOnlyBanner(usage: usage, spentUSD: 9, absence: .noSeat, now: now, locale: usLocale)
  #expect(banner.headline == RunwayInsight.portkeyRunOutSentence(usage: usage, now: now, locale: usLocale, days: .calendar))
  #expect(banner.headline.contains("your Portkey budget runs out"))
  #expect(banner.detail == PortkeyOnly.causeLine(.noSeat, hasBudget: true))
}

@Test func portkeyOnlyBannerOverBudget() {
  let now = utcDate("2026-11-16T00:00:00Z")
  let usage = PortkeyBudget.usage(spentUSD: 13, budgetUSD: 12, resetDate: utcDate("2026-12-01T00:00:00Z"))!
  let banner = RunwayInsight.portkeyOnlyBanner(usage: usage, spentUSD: 13, absence: .noSeat, now: now, locale: usLocale)
  #expect(banner.headline == RunwayInsight.portkeyLimitSentence(usage: usage, locale: usLocale))
}

@Test func portkeyOnlyBannerNothingSpent() {
  let now = utcDate("2026-11-16T00:00:00Z")
  let usage = PortkeyBudget.usage(spentUSD: 0, budgetUSD: 12, resetDate: utcDate("2026-12-01T00:00:00Z"))!
  let banner = RunwayInsight.portkeyOnlyBanner(usage: usage, spentUSD: 0, absence: .noSeat, now: now, locale: usLocale)
  #expect(banner.headline == "Nothing spent on Portkey yet this month.")
}
