import Core
import Foundation
import Testing

let summaryNow = utcDate("2026-10-11T00:00:00Z")
let summaryModelCredits = [
  ModelCredits(model: "gpt-6.1-sol", credits: 900),
  ModelCredits(model: "gpt-6-luna", credits: 300),
  ModelCredits(model: "gemini-3.8-flash", credits: 60),
  ModelCredits(model: "other-model", credits: 40),
  ModelCredits(model: "unpriced-model", credits: nil),
]
let summaryCategoryCredits = [
  CategoryCredits(category: .implementation, credits: 700),
  CategoryCredits(category: .investigation, credits: 400),
  CategoryCredits(category: .planning, credits: 150),
  CategoryCredits(category: .review, credits: 50),
]

@Test func summaryListsCycleRunwayAndTopShares() {
  let text = QuotaSummary.text(
    usage: makeUsage(creditsUsed: 6000),
    now: summaryNow,
    modelCredits: summaryModelCredits,
    categoryCredits: summaryCategoryCredits
  )
  // Shares are of the 1300 priced credits. The unpriced model is left out.
  #expect(text == """
    GitHub Copilot AI credits, cycle 2026-10-01 to 2026-10-31 (UTC)
    Used: 6,000 of 12,000 credits (50% remaining)
    Average daily burn: 600 credits/day
    Projected run-out: 2026-10-21, before the reset on 2026-11-01
    Top models (share of 1,300 credits in local sessions):
    - GPT-6.1 Sol: 900 credits (69%)
    - GPT-6 Luna: 300 credits (23%)
    - Gemini 3.8 Flash: 60 credits (5%)
    Top categories (same local sessions):
    - Implementation: 700 credits (54%)
    - Investigation: 400 credits (31%)
    - Planning: 150 credits (11%)
    """)
  #expect(text.split(separator: "\n").count <= 15)
}

@Test func summaryCategoryPercentsOfThreeEqualCategoriesAddUpTo100() {
  let equalCategoryCredits = [
    CategoryCredits(category: .implementation, credits: 1),
    CategoryCredits(category: .investigation, credits: 1),
    CategoryCredits(category: .planning, credits: 1),
  ]
  let text = QuotaSummary.text(
    usage: makeUsage(creditsUsed: 6000),
    now: summaryNow,
    modelCredits: [ModelCredits(model: "gpt-6.1-sol", credits: 3)],
    categoryCredits: equalCategoryCredits
  )
  let categoryLines = text.split(separator: "\n").drop { !$0.hasPrefix("Top categories") }.dropFirst()
  #expect(categoryLines.map { $0.suffix(5) } == ["(34%)", "(33%)", "(33%)"])
}

@Test func summaryCategoryPercentsMatchTheTopOfTheByTaskCard() {
  let text = QuotaSummary.text(
    usage: makeUsage(creditsUsed: 6000),
    now: summaryNow,
    modelCredits: summaryModelCredits,
    categoryCredits: summaryCategoryCredits
  )
  let cardShares = ShareBreakdown.tasks(summaryCategoryCredits).items.prefix(3).map(\.share)
  let categoryLines = text.split(separator: "\n").drop { !$0.hasPrefix("Top categories") }.dropFirst()
  #expect(cardShares == [54, 31, 11])
  #expect(categoryLines.map { $0.suffix(5) } == cardShares.map { "(\($0)%)" })
}

@Test func summaryAddsOneOutcomesLineWithCountsOnly() {
  let text = QuotaSummary.text(
    usage: makeUsage(creditsUsed: 6000),
    now: summaryNow,
    modelCredits: summaryModelCredits,
    categoryCredits: summaryCategoryCredits,
    outcomes: GitHubOutcomes(prsMerged: 8, prsOpen: 2, prsReviewed: 20, commits: 45)
  )
  let lines = text.split(separator: "\n")
  #expect(lines[4] == "Outcomes: 10 PRs (8 merged, 2 open), 20 PRs reviewed; 600 credits per PR authored")
  #expect(lines.count == 13)
}

@Test func summaryOutcomesLineHandlesZeroPullRequests() {
  let text = QuotaSummary.text(
    usage: makeUsage(creditsUsed: 1000),
    now: summaryNow,
    modelCredits: [],
    categoryCredits: [],
    outcomes: GitHubOutcomes(prsMerged: 0, prsOpen: 0, prsReviewed: 4, commits: 3)
  )
  #expect(text.hasSuffix("Outcomes: 0 PRs (0 merged, 0 open), 4 PRs reviewed; credits per PR authored: none, no PRs yet"))
}

@Test func summarySaysWhenRunOutFallsAfterReset() {
  let text = QuotaSummary.text(usage: makeUsage(creditsUsed: 1000), now: summaryNow, modelCredits: [], categoryCredits: [])
  #expect(text == """
    GitHub Copilot AI credits, cycle 2026-10-01 to 2026-10-31 (UTC)
    Used: 1,000 of 12,000 credits (92% remaining)
    Average daily burn: 100 credits/day
    Projected run-out: after the reset on 2026-11-01
    """)
}

@Test func summaryHasNoRunOutForUnusedOrUnlimitedPlans() {
  let unusedText = QuotaSummary.text(usage: makeUsage(creditsUsed: 0), now: summaryNow, modelCredits: [], categoryCredits: [])
  #expect(unusedText.hasSuffix("Projected run-out: none, no credits used yet"))

  let unlimitedUsage = makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true)
  let unlimitedText = QuotaSummary.text(usage: unlimitedUsage, now: summaryNow, modelCredits: [], categoryCredits: [])
  #expect(unlimitedText == """
    GitHub Copilot AI credits, cycle 2026-10-01 to 2026-10-31 (UTC)
    Used: 500 credits (unlimited plan)
    Average daily burn: 50 credits/day
    """)
}
