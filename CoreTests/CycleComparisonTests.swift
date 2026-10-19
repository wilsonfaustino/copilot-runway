@testable import Core
import Foundation
import Testing

private let comparisonLocale = Locale(identifier: "en_US")

// One entry per UTC day from the start, like Credits.byDay.
private func comparisonDays(_ credits: [Double], from start: String) -> [DailyCredits] {
  let firstDay = utcDate(start)
  return credits.enumerated().map { offset, dayCredits in
    DailyCredits(day: Runway.utcCalendar.date(byAdding: .day, value: offset, to: firstDay)!, credits: dayCredits)
  }
}

// Five full days at 27 credits, then today at 1,000.
private let currentFiveDays = comparisonDays([27, 27, 27, 27, 27, 1_000], from: "2026-10-01T00:00:00Z")
private let previousThirtyDays = comparisonDays(Array(repeating: 20, count: 30), from: "2026-09-01T00:00:00Z")

@Test func comparisonUsesCumulativeCreditsThroughYesterday() throws {
  let comparison = try #require(CycleComparison.compare(current: currentFiveDays, previous: previousThirtyDays))
  // 5 * 27 = 135 against 5 * 20 = 100.
  #expect(comparison == CycleComparison(throughDay: utcDate("2026-10-05T00:00:00Z"), percentDifference: 35))
}

@Test func comparisonLeavesOutTodaysPartialDay() {
  let quietToday = comparisonDays([27, 27, 27, 27, 27, 0], from: "2026-10-01T00:00:00Z")
  #expect(CycleComparison.compare(current: quietToday, previous: previousThirtyDays)
    == CycleComparison.compare(current: currentFiveDays, previous: previousThirtyDays))
}

@Test func comparisonPastTheLastCyclesLengthUsesItsFinalDay() throws {
  // February has 28 days. March day 30 is yesterday, so the comparison uses all of February.
  let february = comparisonDays(Array(repeating: 10, count: 28), from: "2026-02-01T00:00:00Z")
  let march = comparisonDays(Array(repeating: 14, count: 31), from: "2026-03-01T00:00:00Z")
  let comparison = try #require(CycleComparison.compare(current: march, previous: february))
  // 30 * 14 = 420 against 28 * 10 = 280.
  #expect(comparison.percentDifference == 50)
  #expect(comparison.throughDay == utcDate("2026-03-30T00:00:00Z"))
}

@Test func comparisonOnTheLastCyclesFinalDayIndexUsesEveryPreviousDay() throws {
  // Yesterday is day 28, the last day of February.
  let february = comparisonDays(Array(repeating: 10, count: 28), from: "2026-02-01T00:00:00Z")
  let march = comparisonDays(Array(repeating: 10, count: 29), from: "2026-03-01T00:00:00Z")
  let comparison = try #require(CycleComparison.compare(current: march, previous: february))
  #expect(comparison.percentDifference == 0)
}

@Test func comparisonNeedsFiveActiveLastCycleDaysInThePairedRange() {
  // Yesterday is day 10. The last cycle has 4 active days in days 1 to 10 and 10 more after them.
  let current = comparisonDays(Array(repeating: 30, count: 11), from: "2026-10-01T00:00:00Z")
  var previousCredits = Array(repeating: 0.0, count: 30)
  for dayIndex in [0, 1, 2, 3] + Array(20..<30) { previousCredits[dayIndex] = 50 }
  #expect(CycleComparison.compare(current: current, previous: comparisonDays(previousCredits, from: "2026-09-01T00:00:00Z")) == nil)
  previousCredits[9] = 50
  #expect(CycleComparison.compare(current: current, previous: comparisonDays(previousCredits, from: "2026-09-01T00:00:00Z")) != nil)
}

@Test func comparisonWithoutLastCycleCreditsIsNil() {
  let emptyPrevious = comparisonDays(Array(repeating: 0, count: 30), from: "2026-09-01T00:00:00Z")
  #expect(CycleComparison.compare(current: currentFiveDays, previous: emptyPrevious) == nil)
  #expect(CycleComparison.compare(current: currentFiveDays, previous: []) == nil)
}

@Test func comparisonWithoutAFullCurrentDayIsNil() {
  let onlyToday = comparisonDays([500], from: "2026-10-01T00:00:00Z")
  #expect(CycleComparison.compare(current: onlyToday, previous: previousThirtyDays) == nil)
  #expect(CycleComparison.compare(current: [], previous: previousThirtyDays) == nil)
}

@Test func comparisonWithOneFullCurrentDayStillNeedsFiveActiveLastCycleDays() {
  let firstFullDay = comparisonDays([40, 10], from: "2026-10-01T00:00:00Z")
  #expect(CycleComparison.compare(current: firstFullDay, previous: previousThirtyDays) == nil)
}

@Test func comparisonSentenceAbove() {
  let comparison = CycleComparison(throughDay: utcDate("2026-10-17T00:00:00Z"), percentDifference: 35)
  #expect(comparison.sentence(locale: comparisonLocale) == "Local credits through Oct 17 are 35% above the same days of last cycle.")
}

@Test func comparisonSentenceBelow() throws {
  let current = comparisonDays([17.6, 17.6, 17.6, 17.6, 17.6, 0], from: "2026-10-01T00:00:00Z")
  let comparison = try #require(CycleComparison.compare(current: current, previous: previousThirtyDays))
  // 88 against 100.
  #expect(comparison.sentence(locale: comparisonLocale) == "Local credits through Oct 5 are 12% below the same days of last cycle.")
}

@Test func comparisonSentenceAboutTheSameWhenThePercentRoundsToZero() throws {
  let current = comparisonDays([20.08, 20.08, 20.08, 20.08, 20.08, 0], from: "2026-10-01T00:00:00Z")
  let comparison = try #require(CycleComparison.compare(current: current, previous: previousThirtyDays))
  // 100.4 against 100 is 0.4%, which rounds to 0%.
  #expect(comparison.percentDifference == 0)
  #expect(comparison.sentence(locale: comparisonLocale) == "Local credits through Oct 5 are about the same as last cycle.")
}

// MARK: SessionCredits split at the cycle start

private let splitPrices = ["gpt-6.1-sol": efficiencyPrice, "gpt-6-luna": efficiencyPrice]

private func splitTurn(at isoString: String, toolCalls: [ToolCall] = [], records: [(model: String, at: String, credits: Int)]) -> Turn {
  Turn(
    timestamp: utcDate(isoString),
    source: .pi,
    toolCalls: toolCalls,
    records: records.map { record in
      UsageRecord(
        model: record.model,
        timestamp: utcDate(record.at),
        tokens: TokenUsage(input: 0, cachedInput: record.credits * 1_000, cacheWrite: 0, output: record.credits * 1_000)
      )
    }
  )
}

private let splitEditCalls = [ToolCall(name: "edit", filePath: "a.swift")]
private let currentCycleTurns = [
  splitTurn(at: "2026-10-02T09:00:00Z", toolCalls: splitEditCalls, records: [("gpt-6.1-sol", "2026-10-02T09:01:00Z", 30)]),
  splitTurn(at: "2026-10-03T09:00:00Z", records: [("gpt-6-luna", "2026-10-03T09:01:00Z", 12)]),
]
// Records on both sides of the Oct 1 reset. The current half is the turn a parse from Oct 1 gives.
private let straddleTurn = splitTurn(
  at: "2026-09-30T23:50:00Z",
  toolCalls: splitEditCalls,
  records: [("gpt-6.1-sol", "2026-09-30T23:55:00Z", 8), ("gpt-6.1-sol", "2026-10-01T00:05:00Z", 5)]
)
private let straddleTurnCurrentHalf = splitTurn(
  at: "2026-09-30T23:50:00Z", toolCalls: splitEditCalls, records: [("gpt-6.1-sol", "2026-10-01T00:05:00Z", 5)]
)
private let previousCycleTurns = [
  splitTurn(at: "2026-09-03T09:00:00Z", records: [("gpt-6-luna", "2026-09-03T09:01:00Z", 40)]),
  splitTurn(at: "2026-09-10T09:00:00Z", toolCalls: splitEditCalls, records: [("gpt-6.1-sol", "2026-09-10T09:01:00Z", 25)]),
]
private let splitNow = utcDate("2026-10-04T12:00:00Z")

@Test func lastCycleTurnsLeaveEveryCurrentAggregateUnchanged() {
  let currentOnly = SessionCredits.aggregate(
    turns: currentCycleTurns + [straddleTurnCurrentHalf], prices: splitPrices, cycleStart: fixtureCycleStart, now: splitNow
  )
  let withLastCycle = SessionCredits.aggregate(
    turns: previousCycleTurns + [straddleTurn] + currentCycleTurns, prices: splitPrices, cycleStart: fixtureCycleStart, now: splitNow
  )
  #expect(withLastCycle.byModel == currentOnly.byModel)
  #expect(withLastCycle.byCategory == currentOnly.byCategory)
  #expect(withLastCycle.byModelAndCategory == currentOnly.byModelAndCategory)
  #expect(withLastCycle.bySource == currentOnly.bySource)
  #expect(withLastCycle.byDay == currentOnly.byDay)
  #expect(withLastCycle.cacheHits == currentOnly.cacheHits)
  #expect(withLastCycle.lowCacheSentences == currentOnly.lowCacheSentences)
  #expect(withLastCycle.modelEfficiencyNote == currentOnly.modelEfficiencyNote)
  #expect(currentOnly.byModel.compactMap(\.credits).reduce(0, +) > 0)
}

@Test func lastCycleRecordsFillOnlyThePreviousDailySeries() throws {
  let sessionCredits = SessionCredits.aggregate(
    turns: previousCycleTurns + [straddleTurn] + currentCycleTurns, prices: splitPrices, cycleStart: fixtureCycleStart, now: splitNow
  )
  // Sep 1 through Sep 30, one entry per UTC day.
  #expect(sessionCredits.previousByDay.count == 30)
  #expect(sessionCredits.previousByDay.first?.day == utcDate("2026-09-01T00:00:00Z"))
  #expect(sessionCredits.previousByDay.last?.day == utcDate("2026-09-30T00:00:00Z"))
  let previousTotal = sessionCredits.previousByDay.reduce(0) { $0 + $1.credits }
  let currentTotal = sessionCredits.byDay.reduce(0) { $0 + $1.credits }
  // 40 + 25 + 8 credits before Oct 1, 30 + 12 + 5 from Oct 1.
  #expect(abs(previousTotal - 73) < 1e-9)
  #expect(abs(currentTotal - 47) < 1e-9)
  // 3 active last cycle days, so no sentence.
  #expect(sessionCredits.cycleComparisonSentence == nil)
}

@Test func enoughLastCycleDaysGiveTheComparisonSentence() {
  let previousTurns = (1...6).map { day in
    splitTurn(at: "2026-09-0\(day)T09:00:00Z", records: [("gpt-6-luna", "2026-09-0\(day)T09:01:00Z", 10)])
  }
  let currentTurns = (1...5).map { day in
    splitTurn(at: "2026-10-0\(day)T09:00:00Z", records: [("gpt-6-luna", "2026-10-0\(day)T09:01:00Z", 15)])
  }
  let sessionCredits = SessionCredits.aggregate(
    turns: previousTurns + currentTurns, prices: splitPrices, cycleStart: fixtureCycleStart, now: utcDate("2026-10-06T08:00:00Z"),
    locale: comparisonLocale
  )
  // Oct 1 to 5: 75 credits against Sep 1 to 5: 50 credits.
  #expect(sessionCredits.cycleComparisonSentence == "Local credits through Oct 5 are 50% above the same days of last cycle.")
}

@Test func loadReadsTheLastCycleFromPiSessions() throws {
  let piDirectory = FileManager.default.temporaryDirectory.appending(path: "pi-last-cycle-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: piDirectory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: piDirectory) }
  let lines = [("2026-09-12T10:00:00Z", "resp_sep"), ("2026-10-03T10:00:00Z", "resp_oct")].flatMap { isoString, responseId in
    let milliseconds = Int(utcDate(isoString).timeIntervalSince1970 * 1000)
    return [
      #"{"type":"message","message":{"role":"user","content":[],"timestamp":\#(milliseconds)}}"#,
      #"{"type":"message","message":{"role":"assistant","content":[],"provider":"github-copilot","model":"gpt-6-luna","responseId":"\#(responseId)","usage":{"input":1000,"output":1000,"cacheRead":0,"cacheWrite":0},"timestamp":\#(milliseconds + 1000)}}"#,
    ]
  }
  try lines.joined(separator: "\n").write(to: piDirectory.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)
  let sessionCredits = SessionCredits.load(
    since: fixtureCycleStart,
    now: utcDate("2026-10-04T00:00:00Z"),
    piDirectory: piDirectory,
    openCodeDirectory: fixturesDirectory.appending(path: "missing"),
    ompDirectory: fixturesDirectory.appending(path: "missing"),
    priceURL: missingPriceURL
  )
  let previousTotal = sessionCredits.previousByDay.reduce(0) { $0 + $1.credits }
  let currentTotal = sessionCredits.byDay.reduce(0) { $0 + $1.credits }
  #expect(previousTotal > 0)
  #expect(abs(previousTotal - currentTotal) < 1e-9)
  #expect(abs((sessionCredits.byModel.first?.credits ?? 0) - currentTotal) < 1e-9)
}

@Test func openCodeTurnAcrossTheResetMatchesAReadFromTheReset() throws {
  let openCodeDirectory = try makeOpenCodeDataDirectory(fixture: "opencode/cycle-split.sql")
  defer { try? FileManager.default.removeItem(at: openCodeDirectory) }
  let now = utcDate("2026-10-02T00:00:00Z")
  let loaded = SessionCredits.load(
    since: fixtureCycleStart,
    now: now,
    piDirectory: fixturesDirectory.appending(path: "missing"),
    openCodeDirectory: openCodeDirectory,
    ompDirectory: fixturesDirectory.appending(path: "missing"),
    priceURL: missingPriceURL
  )
  let readFromReset = SessionCredits.aggregate(
    turns: try OpenCodeSessionParser.turns(inDirectory: openCodeDirectory, since: fixtureCycleStart),
    prices: PriceTable.bundled, cycleStart: fixtureCycleStart, now: now
  )
  #expect(loaded.byModel == readFromReset.byModel)
  #expect(loaded.byCategory == readFromReset.byCategory)
  #expect(loaded.byModelAndCategory == readFromReset.byModelAndCategory)
  #expect(loaded.bySource == readFromReset.bySource)
  #expect(loaded.byDay == readFromReset.byDay)
  #expect(loaded.modelEfficiencyNote == readFromReset.modelEfficiencyNote)
  #expect(readFromReset.byCategory.map(\.category) == [.investigation])
  #expect(loaded.previousByDay.reduce(0) { $0 + $1.credits } > 0)
  // Without the split, the whole turn takes the plan agent of its Sep 30 message.
  let unsplit = SessionCredits.aggregate(
    turns: try OpenCodeSessionParser.turns(inDirectory: openCodeDirectory, since: utcDate("2026-09-01T00:00:00Z")),
    prices: PriceTable.bundled, cycleStart: fixtureCycleStart, now: now
  )
  #expect(unsplit.byCategory.map(\.category) == [.planning])
}

// MARK: Efficiency and Copy summary with real notes

// Every turn is an edit turn. The first retries turns edit, run a command, then edit the same file again.
private func efficiencyEditTurns(model: String, firstAt: Date, edits: Int, retries: Int = 0, credits: Int) -> [Turn] {
  let retryCalls = splitEditCalls + [ToolCall(name: "bash", command: "swift test")] + splitEditCalls
  return (0..<(edits + retries)).map { offset in
    let turnAt = firstAt.addingTimeInterval(Double(offset) * 60)
    return Turn(
      timestamp: turnAt,
      source: .pi,
      toolCalls: offset < retries ? retryCalls : splitEditCalls,
      records: [UsageRecord(
        model: model,
        timestamp: turnAt.addingTimeInterval(1),
        tokens: TokenUsage(input: 0, cachedInput: 0, cacheWrite: 0, output: credits * 1_000)
      )]
    )
  }
}

private let summaryUsage = makeUsage(creditsUsed: 6_000)

private func summaryText(_ sessionCredits: SessionCredits) -> String {
  QuotaSummary.text(
    usage: summaryUsage, now: splitNow, modelCredits: sessionCredits.byModel, categoryCredits: sessionCredits.byCategory
  )
}

@Test func lastCycleEditTurnsLeaveTheEfficiencyNoteAndCopySummaryUnchanged() throws {
  let currentTurns = efficiencyEditTurns(model: "gpt-6.1-sol", firstAt: utcDate("2026-10-02T09:00:00Z"), edits: 10, retries: 2, credits: 30)
    + efficiencyEditTurns(model: "gpt-6-luna", firstAt: utcDate("2026-10-03T09:00:00Z"), edits: 11, credits: 12)
  // Costlier and retry-heavier than the current cycle, so any leak into the inputs changes the note.
  let previousTurns = efficiencyEditTurns(model: "gpt-6.1-sol", firstAt: utcDate("2026-09-05T09:00:00Z"), edits: 6, retries: 9, credits: 90)
    + efficiencyEditTurns(model: "gpt-6-luna", firstAt: utcDate("2026-09-06T09:00:00Z"), edits: 3, retries: 12, credits: 45)
  // Sol before the reset and Luna after it. The current half is a single-model Luna edit turn.
  let mixedAcrossReset = Turn(
    timestamp: utcDate("2026-09-30T23:50:00Z"),
    source: .pi,
    toolCalls: splitEditCalls,
    records: [
      UsageRecord(model: "gpt-6.1-sol", timestamp: utcDate("2026-09-30T23:55:00Z"), tokens: TokenUsage(input: 0, cachedInput: 0, cacheWrite: 0, output: 70_000)),
      UsageRecord(model: "gpt-6-luna", timestamp: utcDate("2026-10-01T00:05:00Z"), tokens: TokenUsage(input: 0, cachedInput: 0, cacheWrite: 0, output: 12_000)),
    ]
  )
  let mixedCurrentHalf = Turn(
    timestamp: mixedAcrossReset.timestamp,
    source: .pi,
    toolCalls: splitEditCalls,
    records: [mixedAcrossReset.records[1]]
  )
  let currentOnly = SessionCredits.aggregate(
    turns: currentTurns + [mixedCurrentHalf], prices: splitPrices, cycleStart: fixtureCycleStart, now: splitNow
  )
  let withLastCycle = SessionCredits.aggregate(
    turns: previousTurns + [mixedAcrossReset] + currentTurns, prices: splitPrices, cycleStart: fixtureCycleStart, now: splitNow
  )
  let currentOnlyNote = try #require(currentOnly.modelEfficiencyNote)
  #expect(withLastCycle.modelEfficiencyNote == currentOnlyNote)
  #expect(summaryText(withLastCycle) == summaryText(currentOnly))
  #expect(summaryText(currentOnly).contains("Top models"))
}

@Test func loadWithLastCycleEditTurnsKeepsTheEfficiencyNoteAndCopySummary() throws {
  let piDirectory = FileManager.default.temporaryDirectory.appending(path: "pi-efficiency-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: piDirectory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: piDirectory) }
  var responseNumber = 0
  func editLines(model: String, at isoString: String, edits: Int, outputTokens: Int) -> [String] {
    (0..<edits).flatMap { offset -> [String] in
      responseNumber += 1
      let milliseconds = Int(utcDate(isoString).timeIntervalSince1970 * 1000) + offset * 60_000
      return [
        #"{"type":"message","message":{"role":"user","content":[],"timestamp":\#(milliseconds)}}"#,
        #"{"type":"message","message":{"role":"assistant","content":[{"type":"toolCall","id":"call_\#(responseNumber)","name":"edit","arguments":{"path":"a.swift"}}],"provider":"github-copilot","model":"\#(model)","responseId":"resp_\#(responseNumber)","usage":{"input":0,"output":\#(outputTokens),"cacheRead":0,"cacheWrite":0},"timestamp":\#(milliseconds + 1000)}}"#,
      ]
    }
  }
  let lines = editLines(model: "gpt-6.1-sol", at: "2026-09-05T09:00:00Z", edits: 8, outputTokens: 90_000)
    + editLines(model: "gpt-6-luna", at: "2026-09-06T09:00:00Z", edits: 8, outputTokens: 45_000)
    + editLines(model: "gpt-6.1-sol", at: "2026-10-02T09:00:00Z", edits: 10, outputTokens: 30_000)
    + editLines(model: "gpt-6-luna", at: "2026-10-03T09:00:00Z", edits: 11, outputTokens: 12_000)
  try lines.joined(separator: "\n").write(to: piDirectory.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)
  let loaded = SessionCredits.load(
    since: fixtureCycleStart,
    now: splitNow,
    piDirectory: piDirectory,
    openCodeDirectory: fixturesDirectory.appending(path: "missing"),
    ompDirectory: fixturesDirectory.appending(path: "missing"),
    priceURL: missingPriceURL
  )
  let readFromReset = SessionCredits.aggregate(
    turns: PiSessionParser.turns(inDirectory: piDirectory, since: fixtureCycleStart).turns,
    prices: PriceTable.bundled, cycleStart: fixtureCycleStart, now: splitNow
  )
  let note = try #require(readFromReset.modelEfficiencyNote)
  #expect(loaded.modelEfficiencyNote == note)
  #expect(summaryText(loaded) == summaryText(readFromReset))
  #expect(loaded.previousByDay.reduce(0) { $0 + $1.credits } > 0)
}
