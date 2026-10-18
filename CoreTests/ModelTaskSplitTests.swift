import Core
import Foundation
import Testing

private let readCalls = [ToolCall(name: "read", filePath: "a.swift")]
private let editCalls = [ToolCall(name: "edit", filePath: "a.swift")]
private let sevenModels = ["model-a", "model-b", "model-c", "model-d", "model-e", "model-f", "model-g"]
private let sevenModelPrices = Dictionary(uniqueKeysWithValues: sevenModels.map { ($0, efficiencyPrice) })

private func credits(_ modelCategoryCredits: [ModelCategoryCredits], model: String, category: TaskCategory) -> Double {
  modelCategoryCredits.filter { $0.model == model && $0.category == category }.reduce(0) { $0 + $1.credits }
}

private func segmentCredits(_ split: ModelTaskSplit, _ id: ShareItem.ID) -> [Double] {
  (split.segments[id] ?? []).map(\.credits)
}

// Model n spends 70 - 10n credits: model-a 70 down to model-g 10. Half on Implementation, half on Investigation.
private func sevenModelTurns() -> [Turn] {
  sevenModels.enumerated().flatMap { index, model in
    let halfCredits = (70 - 10 * index) / 2
    return [
      efficiencyTurn(toolCalls: editCalls, records: [efficiencyRecord(model: model, credits: halfCredits)]),
      efficiencyTurn(toolCalls: readCalls, records: [efficiencyRecord(model: model, credits: halfCredits)]),
    ]
  }
}

@Test func byModelAndCategoryGivesEachRecordToItsModelAndTheCategoryOfItsTurn() {
  let mixedTurn = efficiencyTurn(
    toolCalls: editCalls,
    records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 10), efficiencyRecord(model: "gpt-6-luna", credits: 4)]
  )
  let readTurn = efficiencyTurn(toolCalls: readCalls, records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 6)])
  let modelCategoryCredits = Credits.byModelAndCategory(turns: [mixedTurn, readTurn], prices: efficiencyPrices)
  #expect(modelCategoryCredits.count == 3)
  #expect(isClose(credits(modelCategoryCredits, model: "gpt-6.1-sol", category: .implementation), 10))
  #expect(isClose(credits(modelCategoryCredits, model: "gpt-6-luna", category: .implementation), 4))
  #expect(isClose(credits(modelCategoryCredits, model: "gpt-6.1-sol", category: .investigation), 6))
}

@Test func byModelAndCategoryTotalsMatchByModelAndByCategory() {
  let timestamp = utcDate("2026-10-05T10:00:00Z")
  let turns = [
    Turn(timestamp: timestamp, source: .pi, toolCalls: readCalls, records: [
      UsageRecord(model: "gpt-6.1-sol", timestamp: timestamp, tokens: millionSolInputTokens),
      UsageRecord(model: "gpt-6-luna", timestamp: timestamp, tokens: TokenUsage(input: 10, cachedInput: 300000, cacheWrite: 200, output: 300)),
      UsageRecord(model: "unpriced-model", timestamp: timestamp, tokens: millionSolInputTokens),
    ]),
    Turn(timestamp: timestamp, source: .opencode, toolCalls: [ToolCall(name: "edit", filePath: "b.swift")], records: [
      UsageRecord(model: "gpt-6-luna", timestamp: timestamp, tokens: millionSolInputTokens),
    ]),
    Turn(timestamp: timestamp, source: .pi, records: [
      UsageRecord(model: "unpriced-model", timestamp: timestamp, tokens: millionSolInputTokens),
    ]),
  ]
  let modelCategoryCredits = Credits.byModelAndCategory(turns: turns, prices: PriceTable.bundled)
  #expect(!modelCategoryCredits.contains { $0.model == "unpriced-model" })
  for modelCredits in Credits.byModel(records: turns.flatMap(\.records), prices: PriceTable.bundled) {
    let modelTotal = modelCategoryCredits.filter { $0.model == modelCredits.model }.reduce(0) { $0 + $1.credits }
    #expect(isClose(modelTotal, modelCredits.credits ?? 0))
  }
  for categoryCredits in Credits.byCategory(turns: turns, prices: PriceTable.bundled) {
    let categoryTotal = modelCategoryCredits.filter { $0.category == categoryCredits.category }.reduce(0) { $0 + $1.credits }
    #expect(isClose(categoryTotal, categoryCredits.credits))
  }
}

@Test func byModelAndCategoryBreaksCreditTiesByModelThenCategory() {
  let turns = [
    efficiencyTurn(toolCalls: editCalls, records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 10), efficiencyRecord(model: "gpt-6-luna", credits: 10)]),
    efficiencyTurn(toolCalls: readCalls, records: [efficiencyRecord(model: "gpt-6-luna", credits: 10)]),
  ]
  let modelCategoryCredits = Credits.byModelAndCategory(turns: turns, prices: efficiencyPrices)
  #expect(modelCategoryCredits.map(\.model) == ["gpt-6-luna", "gpt-6-luna", "gpt-6.1-sol"])
  #expect(modelCategoryCredits.map(\.category) == [.implementation, .investigation, .implementation])
}

@Test func taskSplitIgnoresModelsOutsideTheBreakdownWhenThereIsNoOtherModelsItem() {
  let breakdown = ShareBreakdown.models(
    Credits.byModel(records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 10)], prices: efficiencyPrices), githubCredits: 0
  )
  #expect(breakdown.items.map(\.id) == [.entry("gpt-6.1-sol")])
  let split = ModelTaskSplit(
    breakdown: breakdown,
    modelCategoryCredits: [
      ModelCategoryCredits(model: "gpt-6.1-sol", category: .implementation, credits: 10),
      ModelCategoryCredits(model: "gpt-6-luna", category: .debugging, credits: 5),
    ]
  )
  #expect(split.categories == [.implementation])
  #expect(Set(split.segments.keys) == [.entry("gpt-6.1-sol")])
}

@Test func modelBreakdownNamesUpToTheGivenLimit() {
  let modelCredits = Credits.byModel(records: sevenModelTurns().flatMap(\.records), prices: sevenModelPrices)
  let splitBreakdown = ShareBreakdown.models(
    modelCredits, githubCredits: 280, namedModelLimit: ShareBreakdown.taskSplitModelLimit
  )
  #expect(ShareBreakdown.taskSplitModelLimit == 5)
  #expect(splitBreakdown.items.map(\.id) == sevenModels.prefix(5).map { .entry($0) } + [.otherModels])
  #expect(isClose(splitBreakdown.items[5].credits, 20 + 10))
  // The popover keeps 3 named models.
  #expect(ShareBreakdown.models(modelCredits, githubCredits: 280).items.map(\.id) == sevenModels.prefix(3).map { .entry($0) } + [.otherModels])
}

@Test func taskSplitOfOtherModelsSumsTheFoldedModels() {
  let turns = sevenModelTurns() + [
    efficiencyTurn(toolCalls: editCalls + [ToolCall(name: "bash", command: "swift test")] + editCalls, records: [efficiencyRecord(model: "model-g", credits: 4)])
  ]
  let modelCredits = Credits.byModel(records: turns.flatMap(\.records), prices: sevenModelPrices)
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 0, namedModelLimit: ShareBreakdown.taskSplitModelLimit)
  let split = ModelTaskSplit(
    breakdown: breakdown, modelCategoryCredits: Credits.byModelAndCategory(turns: turns, prices: sevenModelPrices)
  )
  // model-f has 10 + 10, model-g has 5 + 5 and 4 Debugging.
  #expect(split.segments[.otherModels]?.map(\.category) == [.implementation, .investigation, .debugging])
  #expect(segmentCredits(split, .otherModels).map { $0.rounded() } == [15, 15, 4])
  #expect(segmentCredits(split, .entry("model-a")).map { $0.rounded() } == [35, 35])
  for item in breakdown.items {
    #expect(isClose(segmentCredits(split, item.id).reduce(0, +), item.credits))
  }
}

@Test func taskSplitOrdersSegmentsByCategoryTotalAndDropsEmptyCategories() {
  let turns = [
    efficiencyTurn(toolCalls: readCalls, records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 10)]),
    efficiencyTurn(toolCalls: editCalls, records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 2)]),
    efficiencyTurn(toolCalls: editCalls, records: [efficiencyRecord(model: "gpt-6-luna", credits: 30)]),
    efficiencyTurn(toolCalls: readCalls, records: [efficiencyRecord(model: "gpt-6-luna", credits: 0)]),
  ]
  let breakdown = ShareBreakdown.models(
    Credits.byModel(records: turns.flatMap(\.records), prices: efficiencyPrices), githubCredits: 0
  )
  let split = ModelTaskSplit(
    breakdown: breakdown, modelCategoryCredits: Credits.byModelAndCategory(turns: turns, prices: efficiencyPrices)
  )
  // Implementation has 32 credits in all and Investigation 10, so every bar draws Implementation first.
  #expect(split.categories == [.implementation, .investigation])
  #expect(split.segments[.entry("gpt-6.1-sol")]?.map(\.category) == [.implementation, .investigation])
  #expect(split.segments[.entry("gpt-6-luna")]?.map(\.category) == [.implementation])
}

@Test func taskSplitLeavesOutUnpricedModelsAndTheGapItem() {
  let turns = [
    efficiencyTurn(
      toolCalls: editCalls,
      records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 10), efficiencyRecord(model: "unpriced-model", credits: 50)]
    )
  ]
  let modelCredits = Credits.byModel(records: turns.flatMap(\.records), prices: efficiencyPrices)
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 40, namedModelLimit: ShareBreakdown.taskSplitModelLimit)
  let split = ModelTaskSplit(
    breakdown: breakdown, modelCategoryCredits: Credits.byModelAndCategory(turns: turns, prices: efficiencyPrices)
  )
  #expect(breakdown.items.map(\.id) == [.entry("gpt-6.1-sol"), .notInLocalSessions])
  #expect(Set(split.segments.keys) == [.entry("gpt-6.1-sol")])
  #expect(split.segments[.entry("unpriced-model")] == nil)
  #expect(split.segments[.notInLocalSessions] == nil)
}

@Test func taskSplitOfNoSessionsIsEmpty() {
  #expect(Credits.byModelAndCategory(turns: [], prices: efficiencyPrices).isEmpty)
  let split = ModelTaskSplit(breakdown: ShareBreakdown.models([], githubCredits: 0), modelCategoryCredits: [])
  #expect(split.categories.isEmpty)
  #expect(split.segments.isEmpty)
}

@Test func segmentSummaryNamesTheTaskItsShareOfTheModelAndItsCredits() {
  let segment = CategoryCredits(category: .debugging, credits: 1925)
  #expect(ModelTaskSplit.segmentSummary(segment, of: 6210, locale: Locale(identifier: "en_US")) == "Debugging, 31%, 1,925 credits")
  #expect(ModelTaskSplit.segmentSummary(segment, of: 6210, locale: Locale(identifier: "pt_BR")) == "Debugging, 31%, 1.925 credits")
}

@Test func segmentSummaryShowsASmallShareAsBelowOnePercent() {
  let segment = CategoryCredits(category: .planning, credits: 2)
  #expect(ModelTaskSplit.segmentSummary(segment, of: 1000, locale: Locale(identifier: "en_US")) == "Planning, <1%, 2 credits")
}

@Test func rowSummaryListsTheTotalShareAndEveryTaskInBarOrder() {
  let turns = [
    efficiencyTurn(toolCalls: editCalls, records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 600)]),
    efficiencyTurn(toolCalls: readCalls, records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 300)]),
    efficiencyTurn(toolCalls: editCalls, records: [efficiencyRecord(model: "gpt-6-luna", credits: 100)]),
  ]
  let breakdown = ShareBreakdown.models(
    Credits.byModel(records: turns.flatMap(\.records), prices: efficiencyPrices), githubCredits: 0
  )
  let split = ModelTaskSplit(
    breakdown: breakdown, modelCategoryCredits: Credits.byModelAndCategory(turns: turns, prices: efficiencyPrices)
  )
  let solItem = breakdown.items.first { $0.id == .entry("gpt-6.1-sol") }!
  #expect(
    split.rowSummary(for: solItem, locale: usLocale)
      == "900 credits, 90% of all credits. Implementation, 67%, 600 credits. Investigation, 33%, 300 credits."
  )
  let lunaItem = breakdown.items.first { $0.id == .entry("gpt-6-luna") }!
  #expect(split.rowSummary(for: lunaItem, locale: usLocale) == "100 credits, 10% of all credits. Implementation, 100%, 100 credits.")
}

@Test func rowSummaryOfOtherModelsSumsTheFoldedModelsTasks() {
  let modelCredits = Credits.byModel(records: sevenModelTurns().flatMap(\.records), prices: sevenModelPrices)
  let breakdown = ShareBreakdown.models(modelCredits, githubCredits: 0, namedModelLimit: ShareBreakdown.taskSplitModelLimit)
  let split = ModelTaskSplit(
    breakdown: breakdown, modelCategoryCredits: Credits.byModelAndCategory(turns: sevenModelTurns(), prices: sevenModelPrices)
  )
  let otherItem = breakdown.items.first { $0.id == .otherModels }!
  // model-f has 20 and model-g has 10.
  #expect(
    split.rowSummary(for: otherItem, locale: usLocale)
      == "30 credits, \(otherItem.share)% of all credits. Implementation, 50%, 15 credits. Investigation, 50%, 15 credits."
  )
}

@Test func rowSummaryShowsATinySegmentAsBelowOnePercent() {
  let turns = [
    efficiencyTurn(toolCalls: editCalls, records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 998)]),
    efficiencyTurn(toolCalls: readCalls, records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 2)]),
  ]
  let breakdown = ShareBreakdown.models(
    Credits.byModel(records: turns.flatMap(\.records), prices: efficiencyPrices), githubCredits: 0
  )
  let split = ModelTaskSplit(
    breakdown: breakdown, modelCategoryCredits: Credits.byModelAndCategory(turns: turns, prices: efficiencyPrices)
  )
  #expect(
    split.rowSummary(for: breakdown.items[0], locale: usLocale)
      == "1,000 credits, 100% of all credits. Implementation, 100%, 998 credits. Investigation, <1%, 2 credits."
  )
}

@Test func rowSummaryOfAnItemWithoutSegmentsHasTheTotalAndShareOnly() {
  let split = ModelTaskSplit(breakdown: ShareBreakdown.models([], githubCredits: 0), modelCategoryCredits: [])
  let gapItem = ShareItem(id: .notInLocalSessions, name: ShareBreakdown.notInLocalSessionsName, credits: 250, share: 20)
  #expect(split.rowSummary(for: gapItem, locale: usLocale) == "250 credits, 20% of all credits.")
}
