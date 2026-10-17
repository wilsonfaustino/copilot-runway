import Core
import Foundation
import Testing

private func itemCreditsTotal(_ breakdown: ShareBreakdown) -> Double {
  breakdown.items.reduce(0) { $0 + $1.credits }
}

@Test func localBreakdownKeepsOrderAndSharesOfLocalTotal() {
  let breakdown = ShareBreakdown.local(entries: [("Investigation", 600), ("Debugging", 300), ("Planning", 100)])
  #expect(breakdown.shareTotal == 1000)
  #expect(breakdown.items.map(\.name) == ["Investigation", "Debugging", "Planning"])
  #expect(breakdown.items.map(\.share) == [60, 30, 10])
  #expect(breakdown.items.allSatisfy { $0.kind == .entry })
  #expect(breakdown.unit == "local credits")
}

@Test func localBreakdownWithNoCreditsHasZeroShares() {
  #expect(ShareBreakdown.local(entries: []) == ShareBreakdown(shareTotal: 0, items: []))
  let breakdown = ShareBreakdown.local(entries: [("Pi", 0)])
  #expect(breakdown.shareTotal == 0)
  #expect(breakdown.items.map(\.share) == [0])
}

@Test func modelBreakdownAddsGapItemWhenGitHubShowsMore() {
  let modelCredits = [ModelCredits(model: "gpt-6.1-sol", credits: 620), ModelCredits(model: "gpt-6-luna", credits: 250)]
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 1000)
  #expect(breakdown.shareTotal == 1000)
  #expect(breakdown.unit == "GitHub credits")
  #expect(breakdown.items.map(\.name) == ["GPT-6.1 Sol", "GPT-6 Luna", "Not in local sessions"])
  #expect(breakdown.items.map(\.credits) == [620, 250, 130])
  #expect(breakdown.items.map(\.share) == [62, 25, 13])
  #expect(breakdown.items.last?.kind == .notInLocalSessions)
  #expect(itemCreditsTotal(breakdown) == breakdown.shareTotal)
}

@Test func modelBreakdownHasNoGapWhenLocalEqualsGitHub() {
  let breakdown = ShareBreakdown.models([ModelCredits(model: "gpt-6.1-sol", credits: 500)], githubCredits: 500)
  #expect(breakdown.unit == "GitHub credits")
  #expect(breakdown.items.map(\.name) == ["GPT-6.1 Sol"])
  #expect(breakdown.items.map(\.share) == [100])
}

@Test func modelBreakdownUsesLocalTotalWhenLocalShowsMore() {
  let modelCredits = [ModelCredits(model: "gpt-6.1-sol", credits: 900), ModelCredits(model: "gpt-6-luna", credits: 300)]
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 1000)
  #expect(breakdown.shareTotal == 1200)
  #expect(breakdown.unit == "local credits")
  #expect(breakdown.items.map(\.name) == ["GPT-6.1 Sol", "GPT-6 Luna"])
  #expect(breakdown.items.map(\.share) == [75, 25])
  #expect(itemCreditsTotal(breakdown) == breakdown.shareTotal)
}

@Test func modelBreakdownFoldsModelsAfterTheTopThree() {
  let modelCredits = [
    ModelCredits(model: "model-e", credits: 50),
    ModelCredits(model: "model-a", credits: 400),
    ModelCredits(model: "model-d", credits: 100),
    ModelCredits(model: "model-b", credits: 250),
    ModelCredits(model: "model-c", credits: 200),
  ]
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 1000)
  #expect(breakdown.items.map(\.name) == ["model-a", "model-b", "model-c", "Other models"])
  #expect(breakdown.items.map(\.kind) == [.entry, .entry, .entry, .otherModels])
  #expect(breakdown.items.map(\.credits) == [400, 250, 200, 150])
  #expect(breakdown.items.map(\.share) == [40, 25, 20, 15])
}

@Test func modelBreakdownFoldsBeforeTheGapItem() {
  let modelCredits = (1...4).map { ModelCredits(model: "model-\($0)", credits: Double(100 * $0)) }
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 1200)
  #expect(breakdown.items.map(\.name) == ["model-4", "model-3", "model-2", "Other models", "Not in local sessions"])
  #expect(breakdown.items.map(\.credits) == [400, 300, 200, 100, 200])
  #expect(itemCreditsTotal(breakdown) == breakdown.shareTotal)
}

@Test func modelBreakdownDoesNotFoldThreeModels() {
  let modelCredits = (1...3).map { ModelCredits(model: "model-\($0)", credits: Double(100 * $0)) }
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 600)
  #expect(breakdown.items.map(\.name) == ["model-3", "model-2", "model-1"])
}

@Test func modelBreakdownSkipsUnpricedModels() {
  let modelCredits = (1...3).map { ModelCredits(model: "model-\($0)", credits: Double(100 * $0)) }
    + [ModelCredits(model: "unpriced-model", credits: nil)]
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 600)
  #expect(breakdown.items.map(\.name) == ["model-3", "model-2", "model-1"])
}

@Test func modelBreakdownHidesAGapThatRoundsToZeroPercent() {
  // The gap is 2 of 1000 credits, 0.2%.
  let breakdown = ShareBreakdown.models([ModelCredits(model: "gpt-6.1-sol", credits: 998)], githubCredits: 1000)
  #expect(breakdown.shareTotal == 1000)
  #expect(breakdown.items.map(\.name) == ["GPT-6.1 Sol"])
  #expect(breakdown.items.map(\.share) == [100])
}

@Test func modelBreakdownKeepsAGapOfOnePercent() {
  let breakdown = ShareBreakdown.models([ModelCredits(model: "gpt-6.1-sol", credits: 990)], githubCredits: 1000)
  #expect(breakdown.items.map(\.name) == ["GPT-6.1 Sol", "Not in local sessions"])
  #expect(breakdown.items.map(\.share) == [99, 1])
}

@Test func modelBreakdownWithNoLocalSessionsHasNoItems() {
  let breakdown = ShareBreakdown.models([], githubCredits: 800)
  #expect(breakdown == ShareBreakdown(shareTotal: 800, items: [], unit: "GitHub credits"))
  #expect(breakdown.isEmpty)
}

@Test func modelBreakdownWithOnlyUnpricedModelsHasNoItems() {
  let breakdown = ShareBreakdown.models([ModelCredits(model: "unpriced-model", credits: nil)], githubCredits: 800)
  #expect(breakdown.items.isEmpty)
  #expect(breakdown.shareTotal == 800)
}

@Test func modelBreakdownWithNoCreditsIsEmpty() {
  #expect(ShareBreakdown.models([], githubCredits: 0) == ShareBreakdown(shareTotal: 0, items: [], unit: "GitHub credits"))
}

@Test func breakdownIsEmptyWithoutItemsOrCredits() {
  #expect(ShareBreakdown.local(entries: []).isEmpty)
  #expect(ShareBreakdown.local(entries: [("Pi", 0)]).isEmpty)
  #expect(!ShareBreakdown.local(entries: [("Pi", 5)]).isEmpty)
}

@Test func unpricedModelsNoteIsNilWhenEveryModelHasAPrice() {
  #expect(ShareBreakdown.unpricedModelsNote([ModelCredits(model: "gpt-6.1-sol", credits: 620)]) == nil)
  #expect(ShareBreakdown.unpricedModelsNote([]) == nil)
}

@Test func unpricedModelsNoteNamesOneModel() {
  let modelCredits = [ModelCredits(model: "gpt-6.1-sol", credits: 620), ModelCredits(model: "grok-5", credits: nil)]
  #expect(ShareBreakdown.unpricedModelsNote(modelCredits) == "1 model has no price: grok-5")
}

@Test func unpricedModelsNoteSortsSeveralModels() {
  let modelCredits = [
    ModelCredits(model: "grok-5", credits: nil),
    ModelCredits(model: "gpt-6.1-sol", credits: 620),
    ModelCredits(model: "claude-haiku-5-5", credits: nil),
  ]
  #expect(ShareBreakdown.unpricedModelsNote(modelCredits) == "2 models have no price: claude-haiku-5-5, grok-5")
}

@Test func taskBreakdownAddsUncategorizedAtZero() {
  let breakdown = ShareBreakdown.tasks([
    CategoryCredits(category: .implementation, credits: 700), CategoryCredits(category: .investigation, credits: 300),
  ])
  #expect(breakdown.items.map(\.name) == ["Implementation", "Investigation", "Uncategorized"])
  #expect(breakdown.items.map(\.credits) == [700, 300, 0])
  #expect(breakdown.shareTotal == 1000)
}

@Test func taskBreakdownKeepsUncategorizedThatHasCredits() {
  let breakdown = ShareBreakdown.tasks([
    CategoryCredits(category: .implementation, credits: 700), CategoryCredits(category: .uncategorized, credits: 3),
  ])
  #expect(breakdown.items.map(\.name) == ["Implementation", "Uncategorized"])
  #expect(breakdown.items.map(\.credits) == [700, 3])
}

@Test func taskBreakdownWithoutLocalCreditsIsEmpty() {
  #expect(ShareBreakdown.tasks([]).isEmpty)
}

// October 2026: 10,052 GitHub credits, 8,728 in local sessions, 14 Copilot reviews.
private let octoberModelCredits = [ModelCredits(model: "gpt-6.1-sol", credits: 6000), ModelCredits(model: "gpt-6-luna", credits: 2728)]
private let octoberBreakdown = ShareBreakdown.models(octoberModelCredits, githubCredits: 10_052)

@Test func copilotReviewNoteSplitsTheRemainderPerReview() {
  // 1,324 credits not in local sessions over 14 reviews is 94.6 each.
  let note = octoberBreakdown.copilotReviewNote(reviewCount: 14, modelCredits: octoberModelCredits, locale: Locale(identifier: "en_US"))
  #expect(note == "Likely 14 Copilot reviews, ~95 each")
}

@Test func copilotReviewNoteUsesSingularForOneReview() {
  let note = octoberBreakdown.copilotReviewNote(reviewCount: 1, modelCredits: octoberModelCredits, locale: Locale(identifier: "en_US"))
  #expect(note == "Likely 1 Copilot review, ~1,324 credits")
}

@Test func copilotReviewNoteIsNilWithoutReviews() {
  #expect(octoberBreakdown.copilotReviewNote(reviewCount: 0, modelCredits: octoberModelCredits) == nil)
}

@Test func copilotReviewNoteIsNilWithoutNotInLocalSessionsItem() {
  let breakdown = ShareBreakdown.models(octoberModelCredits, githubCredits: 8728)
  #expect(!breakdown.items.contains { $0.kind == .notInLocalSessions })
  #expect(breakdown.copilotReviewNote(reviewCount: 14, modelCredits: octoberModelCredits) == nil)
}

@Test func copilotReviewNoteIsNilWhenALocalModelHasNoPrice() {
  let modelCredits = octoberModelCredits + [ModelCredits(model: "grok-5", credits: nil)]
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 10_052)
  #expect(breakdown.copilotReviewNote(reviewCount: 14, modelCredits: modelCredits) == nil)
}

@Test func modelItemsKeepTheRawIdWhenALabelRepeats() {
  let modelCredits = [ModelCredits(model: "gpt-6-luna", credits: 100), ModelCredits(model: "GPT-6 Luna", credits: 50)]
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 150)
  #expect(breakdown.items.map(\.name) == ["GPT-6 Luna", "GPT-6 Luna"])
  #expect(breakdown.items.map(\.id) == [.entry("gpt-6-luna"), .entry("GPT-6 Luna")])
  #expect(Set(breakdown.items.map(\.id)).count == 2)
}

@Test func lowCachePercentsStayPerModelWhenALabelRepeats() {
  let modelCredits = [ModelCredits(model: "gpt-6-luna", credits: 100), ModelCredits(model: "GPT-6 Luna", credits: 50)]
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 150)
  let lowCachePercents = ShareBreakdown.lowCachePercents([
    ModelCacheHit(model: "gpt-6-luna", rate: 0.9),
    ModelCacheHit(model: "GPT-6 Luna", rate: 0.2),
  ])
  #expect(lowCachePercents == [.entry("GPT-6 Luna"): 20])
  #expect(breakdown.items.map { lowCachePercents[$0.id] } == [nil, 20])
}

@Test func lowCachePercentsKeepOneEntryPerModelAndSkipHealthyOnes() {
  let lowCachePercents = ShareBreakdown.lowCachePercents([
    ModelCacheHit(model: "gpt-6-luna", rate: 0.3),
    ModelCacheHit(model: "gpt-6.1-sol", rate: 0.5),
    ModelCacheHit(model: "grok-5", rate: nil),
  ])
  #expect(lowCachePercents == [.entry("gpt-6-luna"): 30])
}

@Test func modelItemsWithEqualCreditsSortByRawIdNotByLabel() {
  // "GPT-7 Alpha" sorts before "gpt-6-luna" as an id, and after "GPT-6 Luna" as a label.
  let modelCredits = [ModelCredits(model: "gpt-6-luna", credits: 100), ModelCredits(model: "GPT-7 Alpha", credits: 100)]
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 200)
  #expect(breakdown.items.map(\.id) == [.entry("GPT-7 Alpha"), .entry("gpt-6-luna")])
  #expect(breakdown.items.map(\.name) == ["GPT-7 Alpha", "GPT-6 Luna"])
}

@Test func syntheticItemsDoNotShareAnIdWithAModelNamedLikeThem() {
  let modelCredits = [
    ModelCredits(model: "Other models", credits: 400),
    ModelCredits(model: "Not in local sessions", credits: 300),
    ModelCredits(model: "model-c", credits: 200),
    ModelCredits(model: "model-d", credits: 50),
  ]
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 1000)
  #expect(breakdown.items.map(\.name) == ["Other models", "Not in local sessions", "model-c", "Other models", "Not in local sessions"])
  #expect(Set(breakdown.items.map(\.id)).count == 5)
  #expect(breakdown.items.map(\.kind) == [.entry, .entry, .entry, .otherModels, .notInLocalSessions])
}

@Test func unpricedModelsKeepTheRawIdAndLabelInInputOrder() {
  let modelCredits = [
    ModelCredits(model: "grok-5", credits: nil),
    ModelCredits(model: "gpt-6-luna", credits: 10),
    ModelCredits(model: "GPT-6 Luna", credits: nil),
  ]
  let unpricedModels = ShareBreakdown.unpricedModels(modelCredits)
  #expect(unpricedModels.map(\.id) == ["grok-5", "GPT-6 Luna"])
  #expect(unpricedModels.map(\.name) == ["grok-5", "GPT-6 Luna"])
}
