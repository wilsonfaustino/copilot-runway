import Core
import Foundation
import Testing

// Each fixture turn starts at a different hour on 2026-10-07. The fixture files comment each turn.
func categoriesByHour(_ turns: [Turn]) -> [Int: TaskCategory] {
  var utcCalendar = Calendar(identifier: .gregorian)
  utcCalendar.timeZone = TimeZone(identifier: "UTC")!
  return Dictionary(uniqueKeysWithValues: turns.map { turn in
    (utcCalendar.component(.hour, from: turn.timestamp), TaskCategorizer.category(of: turn))
  })
}

func piFixtureCategories() -> [Int: TaskCategory] {
  categoriesByHour(PiSessionParser.turns(inDirectory: turnFixturesDirectory.appending(path: "pi-categories"), since: fixtureCycleStart).turns)
}

func openCodeFixtureCategories() throws -> [Int: TaskCategory] {
  let dataDirectory = try makeOpenCodeDataDirectory(fixture: "turns/opencode.sql")
  defer { try? FileManager.default.removeItem(at: dataDirectory) }
  return categoriesByHour(try OpenCodeSessionParser.turns(inDirectory: dataDirectory, since: fixtureCycleStart))
}

@Test func investigationIsReadsSearchesAndShellWithoutEdits() throws {
  let piCategories = piFixtureCategories()
  let openCodeCategories = try openCodeFixtureCategories()
  #expect(piCategories[1] == .investigation)
  #expect(piCategories[12] == .investigation, "gh pr list is not a review command")
  #expect(openCodeCategories[4] == .investigation, "glob and webfetch")
  #expect(piCategories[2] != .investigation, "a read with an edit")
}

@Test func planningIsPlanAgentOrLongTurnWithoutTools() throws {
  let piCategories = piFixtureCategories()
  let openCodeCategories = try openCodeFixtureCategories()
  #expect(piCategories[8] == .planning, "1,200 output tokens, no tools")
  #expect(piCategories[10] == .planning, "neutral tools only, output at the threshold")
  #expect(openCodeCategories[2] == .planning, "plan agent with a short answer")
  #expect(piCategories[9] != .planning, "200 output tokens, no tools")
}

@Test func implementationIsAnyEditOrWrite() throws {
  let piCategories = piFixtureCategories()
  let openCodeCategories = try openCodeFixtureCategories()
  #expect(piCategories[2] == .implementation, "edit and run, no second edit")
  #expect(piCategories[4] == .implementation, "write")
  #expect(openCodeCategories[7] == .implementation, "patch without a file path")
  #expect(piCategories[1] != .implementation)
}

@Test func debuggingIsEditRunEditTheSameFile() throws {
  let piCategories = piFixtureCategories()
  let openCodeCategories = try openCodeFixtureCategories()
  #expect(piCategories[3] == .debugging)
  #expect(openCodeCategories[3] == .debugging, "patch, shell, then the 1.x edit tool on the same file")
  #expect(piCategories[4] != .debugging, "the second edit is on a different file")
  #expect(piCategories[5] != .debugging, "no run between the two edits")
}

@Test func reviewIsGhPrDiffOrViewWithoutEdits() throws {
  let piCategories = piFixtureCategories()
  let openCodeCategories = try openCodeFixtureCategories()
  #expect(piCategories[6] == .review, "rtk gh pr view and gh pr diff")
  #expect(openCodeCategories[5] == .review)
  #expect(piCategories[7] != .review, "gh pr diff with an edit")
  #expect(piCategories[12] != .review, "gh pr list")
}

@Test func uncategorizedMatchesNoRule() throws {
  let piCategories = piFixtureCategories()
  let openCodeCategories = try openCodeFixtureCategories()
  #expect(piCategories[9] == .uncategorized, "short answer, no tools")
  #expect(piCategories[11] == .uncategorized, "MCP tool only")
  #expect(openCodeCategories[6] == .uncategorized, "skill and question only")
  #expect(piCategories[10] != .uncategorized, "neutral tools with a long answer")
}

@Test func precedenceIsDebuggingImplementationReviewPlanAgentInvestigationPlanning() throws {
  let piCategories = piFixtureCategories()
  let openCodeCategories = try openCodeFixtureCategories()
  #expect(piCategories[3] == .debugging, "Debugging wins over Implementation")
  #expect(piCategories[7] == .implementation, "Implementation wins over Review")
  #expect(piCategories[6] == .review, "Review wins over Investigation")
  #expect(openCodeCategories[1] == .planning, "the plan agent wins over Investigation")
  #expect(TaskCategory.allCases == [.debugging, .implementation, .review, .investigation, .planning, .uncategorized])
}

@Test func planAgentTurnWithReadsIsPlanning() {
  let timestamp = utcDate("2026-10-07T01:00:00Z")
  let reads = [ToolCall(name: "read", filePath: "a.swift"), ToolCall(name: "grep")]
  let planTurn = Turn(timestamp: timestamp, source: .opencode, agent: "plan", toolCalls: reads)
  let buildTurn = Turn(timestamp: timestamp, source: .opencode, agent: "build", toolCalls: reads)
  #expect(TaskCategorizer.category(of: planTurn) == .planning)
  #expect(TaskCategorizer.category(of: buildTurn) == .investigation)
}

@Test func toolNamesMapPerSource() {
  let timestamp = utcDate("2026-10-07T01:00:00Z")
  // glob is an OpenCode search tool. Pi has no glob, so there it is a neutral tool.
  let openCodeGlob = Turn(timestamp: timestamp, source: .opencode, toolCalls: [ToolCall(name: "glob")])
  let piGlob = Turn(timestamp: timestamp, source: .pi, toolCalls: [ToolCall(name: "glob")])
  #expect(TaskCategorizer.category(of: openCodeGlob) == .investigation)
  #expect(TaskCategorizer.category(of: piGlob) == .uncategorized)
}

@Test func creditsByCategoryAddUpToCreditsByModel() {
  let turns = PiSessionParser.turns(inDirectory: turnFixturesDirectory.appending(path: "pi-categories"), since: fixtureCycleStart).turns
  let byCategory = Credits.byCategory(turns: turns, prices: PriceTable.bundled)
  let byModel = Credits.byModel(records: turns.flatMap(\.records), prices: PriceTable.bundled)
  #expect(isClose(byCategory.reduce(0) { $0 + $1.credits }, byModel.compactMap(\.credits).reduce(0, +)))
  #expect(Set(byCategory.map(\.category)) == [.investigation, .implementation, .debugging, .review, .planning, .uncategorized])
}

@Test func creditsByCategorySortsBySpendAndSkipsUnpricedModels() {
  let timestamp = utcDate("2026-10-07T01:00:00Z")
  let millionInputTokens = TokenUsage(input: 1_000_000, cachedInput: 0, cacheWrite: 0, output: 0)
  let turns = [
    Turn(
      timestamp: timestamp,
      source: .pi,
      toolCalls: [ToolCall(name: "read", filePath: "a.swift")],
      records: [UsageRecord(model: "gpt-6-luna", timestamp: timestamp, tokens: millionInputTokens)]
    ),
    Turn(
      timestamp: timestamp,
      source: .opencode,
      toolCalls: [ToolCall(name: "patch", filePath: "a.swift")],
      records: [
        UsageRecord(model: "gpt-6.1-sol", timestamp: timestamp, tokens: TokenUsage(input: 100, cachedInput: 50000, cacheWrite: 1000, output: 2000)),
        UsageRecord(model: "unpriced-model", timestamp: timestamp, tokens: millionInputTokens),
      ]
    ),
  ]
  // Luna above the long context threshold: 1M input tokens at $0.20 = 20 credits.
  #expect(Credits.byCategory(turns: turns, prices: PriceTable.bundled).map(\.category) == [.investigation, .implementation])
  #expect(isClose(Credits.byCategory(turns: turns, prices: PriceTable.bundled)[1].credits, 2.77))
}
