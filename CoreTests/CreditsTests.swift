import Core
import Foundation
import Testing

let solPrice = PriceTable.bundled["gpt-6.1-sol"]!
let lunaPrice = PriceTable.bundled["gpt-6-luna"]!

func isClose(_ actual: Double, _ expected: Double) -> Bool {
  abs(actual - expected) < 0.000001
}

@Test func creditsAreUSDTimesOneHundred() {
  // (100 * 2 + 50000 * 0.1 + 1000 * 2.5 + 2000 * 10) / 1M = $0.0277 = 2.77 credits.
  let tokens = TokenUsage(input: 100, cachedInput: 50000, cacheWrite: 1000, output: 2000)
  #expect(isClose(Credits.credits(for: tokens, price: solPrice), 2.77))
}

@Test func longContextRatesApplyAboveThreshold() {
  // 300210 prompt tokens > 272K: (10 * 0.2 + 300000 * 0.02 + 200 * 0.25 + 300 * 0.75) / 1M = $0.006277.
  let tokens = TokenUsage(input: 10, cachedInput: 300000, cacheWrite: 200, output: 300)
  #expect(isClose(Credits.credits(for: tokens, price: lunaPrice), 0.6277))
}

@Test func thresholdItselfUsesStandardRates() {
  let atThreshold = TokenUsage(input: 272_000, cachedInput: 0, cacheWrite: 0, output: 0)
  let aboveThreshold = TokenUsage(input: 272_001, cachedInput: 0, cacheWrite: 0, output: 0)
  #expect(isClose(Credits.credits(for: atThreshold, price: lunaPrice), 2.72))
  #expect(isClose(Credits.credits(for: aboveThreshold, price: lunaPrice), 5.44002))
}

// Token counts from real messages. The expected values are the cost each client stored, times 100.
@Test func matchesCostStoredByPi() {
  let tokens = TokenUsage(input: 3, cachedInput: 132587, cacheWrite: 4460, output: 5996)
  #expect(isClose(Credits.credits(for: tokens, price: solPrice), 8.43747))
}

@Test func matchesCostStoredByOpenCode() {
  // OpenCode output 201 plus reasoning 36.
  let tokens = TokenUsage(input: 2271, cachedInput: 247528, cacheWrite: 0, output: 237)
  #expect(isClose(Credits.credits(for: tokens, price: solPrice), 3.16648))
}

@Test func creditsByModelSumsPerMessageAndSortsBySpend() {
  let timestamp = utcDate("2026-10-05T10:00:00Z")
  let millionInputTokens = TokenUsage(input: 1_000_000, cachedInput: 0, cacheWrite: 0, output: 0)
  let records = [
    UsageRecord(model: "gpt-6-luna", timestamp: timestamp, tokens: millionInputTokens),
    UsageRecord(model: "unpriced-model", timestamp: timestamp, tokens: millionInputTokens),
    UsageRecord(model: "gpt-6.1-sol", timestamp: timestamp, tokens: TokenUsage(input: 100, cachedInput: 50000, cacheWrite: 1000, output: 2000)),
    UsageRecord(model: "gpt-6-luna", timestamp: timestamp, tokens: TokenUsage(input: 10, cachedInput: 300000, cacheWrite: 200, output: 300)),
  ]
  let byModel = Credits.byModel(records: records, prices: PriceTable.bundled)
  #expect(byModel.map(\.model) == ["gpt-6-luna", "gpt-6.1-sol", "unpriced-model"])
  // 1M input tokens is above the threshold: $0.20, plus the long context message above.
  #expect(isClose(byModel[0].credits!, 20 + 0.6277))
  #expect(isClose(byModel[1].credits!, 2.77))
  #expect(byModel[2].credits == nil)
}

@Test func geminiHasNoLongContextTier() throws {
  let geminiPrice = try #require(PriceTable.bundled["gemini-3.8-flash"])
  // 900K prompt tokens still use the default rates: (400000 * 0.75 + 500000 * 0.075 + 2000 * 3.75) / 1M = $0.345.
  let tokens = TokenUsage(input: 400000, cachedInput: 500000, cacheWrite: 0, output: 2000)
  #expect(isClose(Credits.credits(for: tokens, price: geminiPrice), 34.5))
}

let millionSolInputTokens = TokenUsage(input: 1_000_000, cachedInput: 0, cacheWrite: 0, output: 0)

@Test func creditsBySourceSumsPricedTurnsPerSource() {
  let timestamp = utcDate("2026-10-05T10:00:00Z")
  let turns = [
    Turn(timestamp: timestamp, source: .pi, records: [UsageRecord(model: "gpt-6.1-sol", timestamp: timestamp, tokens: millionSolInputTokens)]),
    Turn(timestamp: timestamp, source: .opencode, records: [
      UsageRecord(model: "gpt-6.1-sol", timestamp: timestamp, tokens: millionSolInputTokens),
      UsageRecord(model: "unpriced-model", timestamp: timestamp, tokens: millionSolInputTokens),
    ]),
    Turn(timestamp: timestamp, source: .opencode, records: [UsageRecord(model: "gpt-6.1-sol", timestamp: timestamp, tokens: millionSolInputTokens)]),
  ]
  // 1M Sol input tokens are above the threshold: $4.00 = 400 credits each.
  let bySource = Credits.bySource(turns: turns, prices: PriceTable.bundled)
  #expect(bySource.map(\.source) == [.opencode, .pi])
  #expect(isClose(bySource[0].credits, 800))
  #expect(isClose(bySource[1].credits, 400))
}

@Test func creditsByDayFillsEveryCycleDayThroughNow() {
  let records = [
    UsageRecord(model: "gpt-6.1-sol", timestamp: utcDate("2026-10-01T09:00:00Z"), tokens: millionSolInputTokens),
    UsageRecord(model: "gpt-6.1-sol", timestamp: utcDate("2026-10-03T12:00:00Z"), tokens: millionSolInputTokens),
    UsageRecord(model: "unpriced-model", timestamp: utcDate("2026-10-03T13:00:00Z"), tokens: millionSolInputTokens),
  ]
  let byDay = Credits.byDay(
    records: records,
    prices: PriceTable.bundled,
    cycleStart: utcDate("2026-10-01T00:00:00Z"),
    now: utcDate("2026-10-04T08:00:00Z"),
    calendar: Runway.utcCalendar
  )
  #expect(byDay.map(\.day) == [
    utcDate("2026-10-01T00:00:00Z"), utcDate("2026-10-02T00:00:00Z"),
    utcDate("2026-10-03T00:00:00Z"), utcDate("2026-10-04T00:00:00Z"),
  ])
  #expect(byDay.map(\.credits) == [400, 0, 400, 0])
}

@Test func creditsByDayUsesTheGivenCalendarDay() {
  // 23:30 UTC on October 2 is 20:30 on October 2 in Sao Paulo, and 01:30 UTC on October 3 is 22:30 on October 2.
  let records = [
    UsageRecord(model: "gpt-6.1-sol", timestamp: utcDate("2026-10-02T23:30:00Z"), tokens: millionSolInputTokens),
    UsageRecord(model: "gpt-6.1-sol", timestamp: utcDate("2026-10-03T01:30:00Z"), tokens: millionSolInputTokens),
  ]
  let cycleStart = utcDate("2026-10-01T00:00:00Z")
  let now = utcDate("2026-10-03T12:00:00Z")
  let utcDays = Credits.byDay(records: records, prices: PriceTable.bundled, cycleStart: cycleStart, now: now, calendar: Runway.utcCalendar)
  #expect(utcDays.map(\.credits) == [0, 400, 400])

  var saoPauloCalendar = Calendar(identifier: .gregorian)
  saoPauloCalendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
  let localDays = Credits.byDay(records: records, prices: PriceTable.bundled, cycleStart: cycleStart, now: now, calendar: saoPauloCalendar)
  // The cycle starts at 21:00 on September 30 in Sao Paulo, so that local day comes first.
  #expect(localDays.map(\.day) == [
    utcDate("2026-09-30T03:00:00Z"), utcDate("2026-10-01T03:00:00Z"),
    utcDate("2026-10-02T03:00:00Z"), utcDate("2026-10-03T03:00:00Z"),
  ])
  #expect(localDays.map(\.credits) == [0, 0, 800, 0])
}
