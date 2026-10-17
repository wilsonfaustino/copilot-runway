import Core
import Foundation
import Testing

// At this output rate, 1,000 output tokens cost 1 credit.
let efficiencyPrice = ModelPrice(standard: TokenRates(input: 0, cachedInput: 0, cacheWrite: 0, output: 10))
let efficiencyPrices = ["gpt-6.1-sol": efficiencyPrice, "gpt-6-luna": efficiencyPrice, "gemini-3.8-flash": efficiencyPrice]
let efficiencyLocale = Locale(identifier: "en_US")

func efficiencyRecord(model: String, credits: Int) -> UsageRecord {
  UsageRecord(
    model: model,
    timestamp: utcDate("2026-10-05T12:00:00Z"),
    tokens: TokenUsage(input: 0, cachedInput: 0, cacheWrite: 0, output: credits * 1_000)
  )
}

func efficiencyTurn(toolCalls: [ToolCall], records: [UsageRecord]) -> Turn {
  Turn(timestamp: utcDate("2026-10-05T12:00:00Z"), source: .pi, toolCalls: toolCalls, records: records)
}

// Implementation turns, then Debugging turns, all at the same credits.
func efficiencyTurns(model: String, edits: Int, retries: Int = 0, credits: Int = 10) -> [Turn] {
  let editCalls = [ToolCall(name: "edit", filePath: "a.swift")]
  let retryCalls = editCalls + [ToolCall(name: "bash", command: "swift test")] + editCalls
  let record = efficiencyRecord(model: model, credits: credits)
  return Array(repeating: efficiencyTurn(toolCalls: editCalls, records: [record]), count: edits)
    + Array(repeating: efficiencyTurn(toolCalls: retryCalls, records: [record]), count: retries)
}

@Test func creditsPerEditTurnAndRetryRateCountImplementationAndDebuggingTurns() {
  let turns = efficiencyTurns(model: "gpt-6.1-sol", edits: 14, credits: 10)
    + efficiencyTurns(model: "gpt-6.1-sol", edits: 0, retries: 4, credits: 19)
  let efficiencies = ModelEfficiency.byModel(turns: turns, prices: efficiencyPrices)
  // (14 * 10 + 4 * 19) / 18 = 12 credits. 4 / 18 = 22.2%.
  #expect(efficiencies == [ModelEfficiency(model: "gpt-6.1-sol", editTurns: 18, retryTurns: 4, creditsPerEditTurn: 12)])
  #expect(efficiencies[0].retryPercent == 22)
}

@Test func nonEditTurnsDoNotChangeModelEfficiency() {
  let editTurns = efficiencyTurns(model: "gpt-6.1-sol", edits: 10)
  let record = efficiencyRecord(model: "gpt-6.1-sol", credits: 500)
  let nonEditTurns = [
    efficiencyTurn(toolCalls: [ToolCall(name: "read", filePath: "a.swift")], records: [record]),
    efficiencyTurn(toolCalls: [ToolCall(name: "bash", command: "gh pr view 12")], records: [record]),
    efficiencyTurn(toolCalls: [], records: [record]),
  ]
  #expect(
    ModelEfficiency.byModel(turns: editTurns + nonEditTurns, prices: efficiencyPrices)
      == ModelEfficiency.byModel(turns: editTurns, prices: efficiencyPrices)
  )
}

@Test func mixedModelTurnsAndTurnsWithoutRecordsAreDropped() {
  let editCalls = [ToolCall(name: "edit", filePath: "a.swift")]
  let mixedTurn = efficiencyTurn(
    toolCalls: editCalls,
    records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 500), efficiencyRecord(model: "gpt-6-luna", credits: 500)]
  )
  let turnWithoutRecords = efficiencyTurn(toolCalls: editCalls, records: [])
  let belowMinimum = efficiencyTurns(model: "gpt-6.1-sol", edits: 9) + [mixedTurn, turnWithoutRecords]
  #expect(ModelEfficiency.byModel(turns: belowMinimum, prices: efficiencyPrices).isEmpty)
  let atMinimum = efficiencyTurns(model: "gpt-6.1-sol", edits: 10) + [mixedTurn, turnWithoutRecords]
  #expect(
    ModelEfficiency.byModel(turns: atMinimum, prices: efficiencyPrices)
      == [ModelEfficiency(model: "gpt-6.1-sol", editTurns: 10, retryTurns: 0, creditsPerEditTurn: 10)]
  )
}

@Test func modelWithoutPriceIsDropped() {
  let turns = efficiencyTurns(model: "unknown-model", edits: 12) + efficiencyTurns(model: "gpt-6-luna", edits: 10)
  #expect(ModelEfficiency.byModel(turns: turns, prices: efficiencyPrices).map(\.model) == ["gpt-6-luna"])
}

@Test func modelsUnderMinimumEditTurnsAreHidden() {
  let turns = efficiencyTurns(model: "gpt-6.1-sol", edits: 10) + efficiencyTurns(model: "gpt-6-luna", edits: 6, retries: 3)
  #expect(ModelEfficiency.byModel(turns: turns, prices: efficiencyPrices).map(\.model) == ["gpt-6.1-sol"])
}

@Test func noteComparesTheTwoModelsWithMostEditTurns() {
  let turns = efficiencyTurns(model: "gpt-6.1-sol", edits: 18, retries: 4, credits: 10)
    + efficiencyTurns(model: "gpt-6-luna", edits: 14, retries: 4, credits: 6)
    + efficiencyTurns(model: "gemini-3.8-flash", edits: 10, credits: 1)
  let efficiencies = ModelEfficiency.byModel(turns: turns, prices: efficiencyPrices)
  #expect(efficiencies.map(\.model) == ["gpt-6.1-sol", "gpt-6-luna", "gemini-3.8-flash"])
  #expect(
    ModelEfficiency.note(efficiencies, locale: efficiencyLocale)
      == "GPT-6 Luna costs 40% less per edit turn than GPT-6.1 Sol. Retry rate 22% against 18%."
  )
}

@Test func noteForOneModelGivesItsCreditsPerEditTurn() {
  let turns = efficiencyTurns(model: "gpt-6.1-sol", edits: 14, credits: 10)
    + efficiencyTurns(model: "gpt-6.1-sol", edits: 0, retries: 4, credits: 19)
  let efficiencies = ModelEfficiency.byModel(turns: turns, prices: efficiencyPrices)
  #expect(
    ModelEfficiency.note(efficiencies, locale: efficiencyLocale)
      == "GPT-6.1 Sol costs 12 credits per edit turn. Retry rate 22%."
  )
  let cheap = ModelEfficiency(model: "gpt-6-luna", editTurns: 12, retryTurns: 1, creditsPerEditTurn: 0.0342)
  #expect(ModelEfficiency.note([cheap], locale: efficiencyLocale) == "GPT-6 Luna costs 0.034 credits per edit turn. Retry rate 8%.")
  let one = ModelEfficiency(model: "gpt-6-luna", editTurns: 12, retryTurns: 0, creditsPerEditTurn: 1.2)
  #expect(ModelEfficiency.note([one], locale: efficiencyLocale) == "GPT-6 Luna costs 1 credit per edit turn. Retry rate 0%.")
}

@Test func noteIsNilWithoutQualifyingModels() {
  #expect(ModelEfficiency.note([], locale: efficiencyLocale) == nil)
  let turns = efficiencyTurns(model: "gpt-6.1-sol", edits: 9)
  #expect(ModelEfficiency.note(ModelEfficiency.byModel(turns: turns, prices: efficiencyPrices), locale: efficiencyLocale) == nil)
}

@Test func noteForTwoZeroCostModelsSaysSameCost() {
  let turns = efficiencyTurns(model: "gpt-6.1-sol", edits: 8, retries: 2, credits: 0)
    + efficiencyTurns(model: "gpt-6-luna", edits: 10, credits: 0)
  let efficiencies = ModelEfficiency.byModel(turns: turns, prices: efficiencyPrices)
  #expect(efficiencies.map(\.creditsPerEditTurn) == [0, 0])
  #expect(
    ModelEfficiency.note(efficiencies, locale: efficiencyLocale)
      == "GPT-6 Luna and GPT-6.1 Sol cost the same per edit turn. Retry rate 0% against 20%."
  )
}

@Test func noteForOneZeroCostModelComparesAgainstTheOther() {
  let free = efficiencyTurns(model: "gpt-6-luna", edits: 10, credits: 0)
  let paid = efficiencyTurns(model: "gpt-6.1-sol", edits: 8, retries: 2, credits: 10)
  #expect(
    ModelEfficiency.note(ModelEfficiency.byModel(turns: free + paid, prices: efficiencyPrices), locale: efficiencyLocale)
      == "GPT-6 Luna costs 100% less per edit turn than GPT-6.1 Sol. Retry rate 0% against 20%."
  )
  let freeSol = efficiencyTurns(model: "gpt-6.1-sol", edits: 8, retries: 2, credits: 0)
  let paidLuna = efficiencyTurns(model: "gpt-6-luna", edits: 10, credits: 10)
  #expect(
    ModelEfficiency.note(ModelEfficiency.byModel(turns: freeSol + paidLuna, prices: efficiencyPrices), locale: efficiencyLocale)
      == "GPT-6.1 Sol costs 100% less per edit turn than GPT-6 Luna. Retry rate 20% against 0%."
  )
}

@Test func noteForExactlyEqualPositiveCostsSaysSameCost() {
  let turns = efficiencyTurns(model: "gpt-6.1-sol", edits: 8, retries: 2, credits: 10)
    + efficiencyTurns(model: "gpt-6-luna", edits: 10, credits: 10)
  #expect(
    ModelEfficiency.note(ModelEfficiency.byModel(turns: turns, prices: efficiencyPrices), locale: efficiencyLocale)
      == "GPT-6 Luna and GPT-6.1 Sol cost the same per edit turn. Retry rate 0% against 20%."
  )
}

@Test func noteComparesTheLowestModelIdsWhenEditTurnCountsTie() {
  let flash = efficiencyTurns(model: "gemini-3.8-flash", edits: 7, retries: 3, credits: 4)
  let luna = efficiencyTurns(model: "gpt-6-luna", edits: 9, retries: 1, credits: 8)
  let sol = efficiencyTurns(model: "gpt-6.1-sol", edits: 10, credits: 1)
  let expected = "Gemini 3.8 Flash costs 50% less per edit turn than GPT-6 Luna. Retry rate 30% against 10%."
  for orderedTurns in [flash + luna + sol, sol + luna + flash, luna + sol + flash, sol + flash + luna] {
    let efficiencies = ModelEfficiency.byModel(turns: orderedTurns, prices: efficiencyPrices)
    #expect(efficiencies.map(\.model) == ["gemini-3.8-flash", "gpt-6-luna", "gpt-6.1-sol"])
    #expect(ModelEfficiency.note(efficiencies, locale: efficiencyLocale) == expected)
  }
}

@Test func noteKeepsOrderWhenFirstModelIsAlreadyCheaper() {
  let luna = ModelEfficiency(model: "gpt-6-luna", editTurns: 11, retryTurns: 2, creditsPerEditTurn: 2)
  let sol = ModelEfficiency(model: "gpt-6.1-sol", editTurns: 11, retryTurns: 1, creditsPerEditTurn: 3)
  // 1 - 2 / 3 = 33.3% less. 2 / 11 = 18.2%, 1 / 11 = 9.1%.
  #expect(
    ModelEfficiency.note([luna, sol], locale: efficiencyLocale)
      == "GPT-6 Luna costs 33% less per edit turn than GPT-6.1 Sol. Retry rate 18% against 9%."
  )
}

@Test func creditsPerEditTurnDividesModelTotalByTurnsNotRecords() {
  let records = [efficiencyRecord(model: "gpt-6.1-sol", credits: 4), efficiencyRecord(model: "gpt-6.1-sol", credits: 6)]
  let editCalls = [ToolCall(name: "edit", filePath: "a.swift")]
  let turns = Array(repeating: efficiencyTurn(toolCalls: editCalls, records: records), count: 10)
  let efficiencies = ModelEfficiency.byModel(turns: turns, prices: efficiencyPrices)
  let totalCredits = Credits.byModel(records: turns.flatMap(\.records), prices: efficiencyPrices).first?.credits
  #expect(totalCredits == 100)
  #expect(efficiencies == [ModelEfficiency(model: "gpt-6.1-sol", editTurns: 10, retryTurns: 0, creditsPerEditTurn: 10)])
}

@Test func turnWithPricedAndUnknownModelRecordsDoesNotCountTowardMinimum() {
  let editCalls = [ToolCall(name: "edit", filePath: "a.swift")]
  let pricedAndUnknownTurn = efficiencyTurn(
    toolCalls: editCalls,
    records: [efficiencyRecord(model: "gpt-6.1-sol", credits: 10), efficiencyRecord(model: "unknown-model", credits: 10)]
  )
  let turns = efficiencyTurns(model: "gpt-6.1-sol", edits: 9) + [pricedAndUnknownTurn]
  #expect(ModelEfficiency.byModel(turns: turns, prices: efficiencyPrices).isEmpty)
}

@Test func notePercentsRoundToWholeNumbers() {
  let sol = ModelEfficiency(model: "gpt-6.1-sol", editTurns: 12, retryTurns: 1, creditsPerEditTurn: 3)
  let luna = ModelEfficiency(model: "gpt-6-luna", editTurns: 11, retryTurns: 2, creditsPerEditTurn: 2)
  // 1 - 2 / 3 = 33.3% less. 2 / 11 = 18.2%, 1 / 12 = 8.3%.
  #expect(
    ModelEfficiency.note([sol, luna], locale: efficiencyLocale)
      == "GPT-6 Luna costs 33% less per edit turn than GPT-6.1 Sol. Retry rate 18% against 8%."
  )
  let roundsUpSol = ModelEfficiency(model: "gpt-6.1-sol", editTurns: 12, retryTurns: 5, creditsPerEditTurn: 3)
  let roundsUpLuna = ModelEfficiency(model: "gpt-6-luna", editTurns: 12, retryTurns: 5, creditsPerEditTurn: 1)
  // 1 - 1 / 3 = 66.7% less. 5 / 12 = 41.7%.
  #expect(
    ModelEfficiency.note([roundsUpSol, roundsUpLuna], locale: efficiencyLocale)
      == "GPT-6 Luna costs 67% less per edit turn than GPT-6.1 Sol. Retry rate 42% against 42%."
  )
  let sameCost = ModelEfficiency(model: "gpt-6-luna", editTurns: 11, retryTurns: 2, creditsPerEditTurn: 2.99)
  #expect(
    ModelEfficiency.note([sol, sameCost], locale: efficiencyLocale)
      == "GPT-6 Luna and GPT-6.1 Sol cost the same per edit turn. Retry rate 18% against 8%."
  )
}
