import Core
import Foundation
import Testing

let copilotSessionStateDirectory = fixturesDirectory.appending(path: "copilot/session-state")
let copilotSyntheticDirectory = fixturesDirectory.appending(path: "copilot/synthetic")
let copilotCycleStart = utcDate("2026-11-01T00:00:00Z")
let cliSessionId = "563cb355-abd4-4190-89cf-44744043a6c4"
let appSessionId = "6551f32e-bef2-4017-b9a8-a17798cd528e"
// totalNanoAiu of the fixture sessions, at 1e9 nano AIU per credit.
let cliBilledCredits = 645_019_000 / 1e9
let appBilledCredits = 986_430_200 / 1e9

func copilotFixtureTurns() -> [Turn] {
  CopilotSessionParser.turns(inDirectory: copilotSessionStateDirectory, since: copilotCycleStart).turns
}

func copilotFixtureSessionCredits() -> SessionCredits {
  SessionCredits.load(
    since: copilotCycleStart,
    now: utcDate("2026-11-05T00:00:00Z"),
    piDirectory: fixturesDirectory.appending(path: "missing/pi"),
    openCodeDirectory: fixturesDirectory.appending(path: "missing"),
    ompDirectory: fixturesDirectory.appending(path: "missing/omp"),
    copilotDirectory: copilotSessionStateDirectory,
    priceURL: missingPriceURL
  )
}

// inputTokens includes cache reads and writes, so the uncached input is 3 on every record.
@Test func copilotParserReadsCliUsageRecords() throws {
  let cliTurn = try #require(copilotFixtureTurns().first { $0.source == .copilotCli })
  #expect(cliTurn.sessionId == cliSessionId)
  #expect(cliTurn.directory == "/redacted/project")
  #expect(cliTurn.timestamp == ISO8601DateFormatter.fractionalSeconds.date(from: "2026-11-04T18:28:33.041Z"))
  #expect(cliTurn.records.map(\.tokens) == [
    TokenUsage(input: 3, cachedInput: 0, cacheWrite: 26385, output: 432),
    TokenUsage(input: 3, cachedInput: 26385, cacheWrite: 8259, output: 279),
    TokenUsage(input: 3, cachedInput: 34644, cacheWrite: 7228, output: 499),
  ])
  #expect(cliTurn.records.map(\.billedCredits) == [0.3514425, 0.1436025, 0.149974])
  #expect(cliTurn.records.allSatisfy { $0.model == "gpt-6-luna" })
}

// The CLI session was billed at the PriceTable rate, so the nano AIU conversion must give the same credits.
@Test func copilotCliBilledCreditsMatchPriceTable() throws {
  let cliTurn = try #require(copilotFixtureTurns().first { $0.source == .copilotCli })
  let price = try #require(PriceTable.bundled["gpt-6-luna"])
  for record in cliTurn.records {
    let billedCredits = try #require(record.billedCredits)
    #expect(abs(billedCredits - Credits.credits(for: record.tokens, price: price)) < 1e-9)
  }
}

@Test func copilotFixturesGiveOneRowPerClient() throws {
  let sessionCredits = copilotFixtureSessionCredits()
  #expect(sessionCredits.warning == nil)
  #expect(sessionCredits.bySource.map(\.source) == [.copilotApp, .copilotCli])
  let cliCredits = try #require(sessionCredits.bySource.first { $0.source == .copilotCli }?.credits)
  let appCredits = try #require(sessionCredits.bySource.first { $0.source == .copilotApp }?.credits)
  #expect(abs(cliCredits - cliBilledCredits) < 1e-9)
  #expect(abs(appCredits - appBilledCredits) < 1e-9)
  let modelTotal = sessionCredits.byModel.compactMap(\.credits).reduce(0, +)
  #expect(abs(modelTotal - (cliBilledCredits + appBilledCredits)) < 1e-9)
}

// The app session was billed at 70% of the price card. The credits come from totalNanoAiu, not from PriceTable.
@Test func copilotAppCreditsComeFromNanoAiuNotPriceTable() throws {
  let appTurn = try #require(copilotFixtureTurns().first { $0.source == .copilotApp })
  #expect(appTurn.sessionId == appSessionId)
  #expect(appTurn.records.count == 9)
  let price = try #require(PriceTable.bundled["gpt-6-luna"])
  let priceTableCredits = appTurn.records.reduce(0) { $0 + Credits.credits(for: $1.tokens, price: price) }
  #expect(abs(priceTableCredits / appBilledCredits - 1.4286) < 1e-4)
  let appCredits = try #require(copilotFixtureSessionCredits().bySource.first { $0.source == .copilotApp }?.credits)
  #expect(abs(appCredits - appBilledCredits) < 1e-9)
}

// The CLI turn only views files. The app turn creates a file with apply_patch, runs it, then patches it again.
@Test func copilotFixtureTurnsGetCategories() throws {
  let turns = copilotFixtureTurns()
  let cliTurn = try #require(turns.first { $0.source == .copilotCli })
  let appTurn = try #require(turns.first { $0.source == .copilotApp })
  #expect(cliTurn.toolCalls.count == 10)
  #expect(TaskCategorizer.category(of: cliTurn) == .investigation)
  #expect(appTurn.toolCalls.filter { $0.name == "apply_patch" }.map(\.filePath) == ["/redacted/project/file15", "/redacted/project/file15"])
  #expect(TaskCategorizer.category(of: appTurn) == .debugging)
}

// Kept: the first u-1 record. Skipped: isByok true, provider openai, u-1 again, and a cut last line.
@Test func copilotParserKeepsOnlyCopilotBilledRecords() throws {
  let copilotTurns = CopilotSessionParser.turns(inDirectory: copilotSyntheticDirectory, since: copilotCycleStart)
  #expect(!copilotTurns.hasUndecodableFile)
  let turn = try #require(copilotTurns.turns.first)
  #expect(copilotTurns.turns.count == 1)
  #expect(turn.sessionId == "filters")
  #expect(turn.records == [
    UsageRecord(
      model: "gpt-6-luna",
      timestamp: utcDate("2026-11-02T10:00:05Z"),
      tokens: TokenUsage(input: 120, cachedInput: 0, cacheWrite: 10, output: 20),
      billedCredits: 2
    ),
  ])
}

// The hermes-agent session and the folder without workspace.yaml both hold a valid Copilot record.
@Test func copilotParserSkipsUnknownClientsAndFoldersWithoutWorkspace() {
  let copilotTurns = CopilotSessionParser.turns(inDirectory: copilotSyntheticDirectory, since: copilotCycleStart)
  #expect(copilotTurns.turns.map(\.sessionId) == ["filters"])
  #expect(copilotTurns.turns.allSatisfy { $0.source == .copilotCli })
}

@Test func copilotMcpPullRequestReadIsReview() throws {
  let turn = try #require(CopilotSessionParser.turns(inDirectory: copilotSyntheticDirectory, since: copilotCycleStart).turns.first)
  #expect(turn.toolCalls.map(\.name) == ["github-mcp-server-pull_request_read"])
  #expect(TaskCategorizer.category(of: turn) == .review)
}

@Test func copilotParserWithoutSessionStateReturnsNothing() {
  let copilotTurns = CopilotSessionParser.turns(inDirectory: fixturesDirectory.appending(path: "missing"), since: copilotCycleStart)
  #expect(copilotTurns.turns.isEmpty)
  #expect(!copilotTurns.hasUndecodableFile)
}

@Test func copilotRecordsBeforeCycleAreSkipped() {
  let copilotTurns = CopilotSessionParser.turns(inDirectory: copilotSessionStateDirectory, since: utcDate("2026-11-04T18:28:50Z"))
  #expect(copilotTurns.turns.flatMap(\.records).map(\.billedCredits) == [0.149974] + [
    350493500, 98998200, 135915850, 77602000, 95026750, 60031300, 58667700, 50339100, 59355800,
  ].map { $0 / 1e9 })
}

extension ISO8601DateFormatter {
  static var fractionalSeconds: ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }
}

// Each user.message starts a turn. The first prompt edits a file, the second only views it.
@Test func copilotSessionWithTwoPromptsGivesTwoTurnsWithTheirOwnCategories() {
  let copilotTurns = CopilotSessionParser.turns(inDirectory: fixturesDirectory.appending(path: "copilot/two-prompts"), since: copilotCycleStart)
  #expect(copilotTurns.turns.map { $0.records.map(\.billedCredits) } == [[1], [0.5]])
  #expect(copilotTurns.turns.map(TaskCategorizer.category(of:)) == [.implementation, .investigation])
  #expect(copilotTurns.turns.map(\.timestamp) == [utcDate("2026-11-02T10:00:00Z"), utcDate("2026-11-02T10:10:00Z")])
}

@Test func copilotEventsFileThatDoesNotDecodeGivesNoRecordsAndAWarning() {
  let corruptDirectory = fixturesDirectory.appending(path: "copilot/corrupt")
  let copilotTurns = CopilotSessionParser.turns(inDirectory: corruptDirectory, since: copilotCycleStart)
  #expect(copilotTurns.turns.isEmpty)
  #expect(copilotTurns.hasUndecodableFile)
  let sessionCredits = SessionCredits.load(
    since: copilotCycleStart,
    now: utcDate("2026-11-05T00:00:00Z"),
    piDirectory: fixturesDirectory.appending(path: "missing/pi"),
    openCodeDirectory: fixturesDirectory.appending(path: "missing"),
    ompDirectory: fixturesDirectory.appending(path: "missing/omp"),
    copilotDirectory: corruptDirectory,
    priceURL: missingPriceURL
  )
  #expect(sessionCredits.warning == "Cannot read some Copilot sessions.")
  #expect(sessionCredits.byModel.isEmpty)
}

// One billed record and one record without totalNanoAiu, for a model that has no price.
@Test func copilotModelWithBilledAndUnbilledRecordsKeepsTheBilledSubtotalAndIsMissingAPrice() {
  let sessionCredits = SessionCredits.load(
    since: copilotCycleStart,
    now: utcDate("2026-11-05T00:00:00Z"),
    piDirectory: fixturesDirectory.appending(path: "missing/pi"),
    openCodeDirectory: fixturesDirectory.appending(path: "missing"),
    ompDirectory: fixturesDirectory.appending(path: "missing/omp"),
    copilotDirectory: fixturesDirectory.appending(path: "copilot/partial-billing"),
    priceURL: missingPriceURL
  )
  #expect(sessionCredits.byModel == [ModelCredits(model: "demo-unpriced-model", credits: 2, hasUnpricedRecords: true)])
  #expect(ShareBreakdown.unpricedModelsNote(sessionCredits.byModel) == "1 model has no price: demo-unpriced-model")
}
