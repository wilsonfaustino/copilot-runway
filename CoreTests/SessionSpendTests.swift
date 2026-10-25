import Core
import Foundation
import Testing

let projectFixturesDirectory = fixturesDirectory.appending(path: "projects")
let englishLocale = Locale(identifier: "en_US")

@Test func openCodeTurnsCarryTheSessionFolderParentAndProjectRoot() throws {
  let dataDirectory = try makeOpenCodeDataDirectory(fixture: "opencode/projects.sql")
  defer { try? FileManager.default.removeItem(at: dataDirectory) }
  let turnsBySession = Dictionary(
    grouping: try OpenCodeSessionParser.turns(inDirectory: dataDirectory, since: fixtureCycleStart), by: { $0.sessionId ?? "" }
  )
  let rootTurn = try #require(turnsBySession["ses_root"]?.first)
  #expect(rootTurn.directory == "/Users/example/orca/workspaces/runway-app/fix-chart")
  #expect(rootTurn.projectRoot == "/Users/example/www/acme/runway-app")
  #expect(rootTurn.parentSessionId == nil)
  let childTurn = try #require(turnsBySession["ses_child"]?.first)
  #expect(childTurn.parentSessionId == "ses_root")
  #expect(childTurn.projectRoot == "/Users/example/www/acme/runway-app")
  #expect(turnsBySession["ses_home"]?.first?.projectRoot == "/")
  // A message whose session has no session_v2 row still counts, without a folder.
  let missingTurn = try #require(turnsBySession["ses_missing"]?.first)
  #expect(missingTurn.directory == nil)
  #expect(missingTurn.projectRoot == nil)
  #expect(missingTurn.records.count == 1)
  #expect(turnsBySession.values.joined().count == 6)
}

// Older databases have no session_v2 or project table. The turns keep their session id and get no folder.
@Test func openCodeTurnsWithoutSessionTableHaveNoFolder() throws {
  let dataDirectory = try makeOpenCodeDataDirectory()
  defer { try? FileManager.default.removeItem(at: dataDirectory) }
  let turns = try OpenCodeSessionParser.turns(inDirectory: dataDirectory, since: fixtureCycleStart)
  #expect(!turns.isEmpty)
  #expect(turns.allSatisfy { $0.sessionId == "ses_1" && $0.directory == nil && $0.projectRoot == nil && $0.parentSessionId == nil })
}

@Test func piTurnsCarryTheSessionHeaderIdAndFolder() {
  let turns = PiSessionParser.turns(inDirectory: projectFixturesDirectory.appending(path: "pi"), since: fixtureCycleStart).turns
  #expect(turns.count == 2)
  #expect(turns.allSatisfy { $0.sessionId == "pi-session-1" })
  #expect(turns.allSatisfy { $0.directory == "/Users/example/orca/workspaces/runway-app/fix-chart" })
  #expect(turns.allSatisfy { $0.projectRoot == nil && $0.parentSessionId == nil })
}

// omp writes a title entry before the session header.
@Test func ompTurnsCarryTheSessionHeaderAfterTheTitle() {
  let turns = PiSessionParser.turns(inDirectory: projectFixturesDirectory.appending(path: "omp"), source: .omp, since: fixtureCycleStart).turns
  #expect(turns.count == 1)
  #expect(turns.first?.sessionId == "omp-session-1")
  #expect(turns.first?.directory == "/Users/example/www/acme/billing-api")
}

@Test func piFileWithoutCwdHasNoFolder() {
  let turns = PiSessionParser.turns(inDirectory: fixturesDirectory.appending(path: "pi/undecodable"), since: fixtureCycleStart).turns
  #expect(turns.map(\.sessionId) == ["session-good"])
  #expect(turns.map(\.directory) == [nil])
}

func projectFixtureSessionCredits(openCodeDirectory: URL) -> SessionCredits {
  SessionCredits.load(
    since: fixtureCycleStart,
    now: sessionCreditsNow,
    piDirectory: projectFixturesDirectory.appending(path: "pi"),
    openCodeDirectory: openCodeDirectory,
    ompDirectory: projectFixturesDirectory.appending(path: "omp"),
    priceURL: missingPriceURL
  )
}

@Test func projectAndSessionTotalsEqualTheModelTotal() throws {
  let openCodeDirectory = try makeOpenCodeDataDirectory(fixture: "opencode/projects.sql")
  defer { try? FileManager.default.removeItem(at: openCodeDirectory) }
  let sessionCredits = projectFixtureSessionCredits(openCodeDirectory: openCodeDirectory)
  let modelTotal = sessionCredits.byModel.compactMap(\.credits).reduce(0, +)
  #expect(sessionCredits.warning == nil)
  #expect(modelTotal > 0)
  #expect(abs(sessionCredits.byProject.reduce(0) { $0 + $1.credits } - modelTotal) < 1e-9)
  #expect(abs(sessionCredits.bySession.reduce(0) { $0 + $1.credits } - modelTotal) < 1e-9)
  // ses_child folds into ses_root: 5 OpenCode sessions, 1 Pi and 1 omp.
  #expect(sessionCredits.bySession.count == 7)
  #expect(!sessionCredits.bySession.contains { $0.id == "ses_child" })
  #expect(sessionCredits.bySession.first { $0.id == "ses_root" }?.turnCount == 2)
  // The OpenCode root and the old project folder both name runway-app.
  #expect(sessionCredits.bySession.first { $0.id == "ses_old" }?.project == "runway-app")
  #expect(sessionCredits.bySession.first { $0.id == "ses_root" }?.project == "runway-app")
  #expect(sessionCredits.byProject.map(\.name).filter { $0 == "runway-app" }.count == 1)
}

func sessionTurn(
  _ isoString: String, sessionId: String?, parent: String? = nil, source: SessionSource = .opencode,
  model: String = "gpt-6-luna", output: Int = 10, toolCalls: [ToolCall] = []
) -> Turn {
  Turn(
    timestamp: utcDate(isoString), source: source, toolCalls: toolCalls,
    records: [UsageRecord(model: model, timestamp: utcDate(isoString), tokens: TokenUsage(input: 100, cachedInput: 0, cacheWrite: 0, output: output))],
    sessionId: sessionId, parentSessionId: parent
  )
}

let sessionPrices = PriceTable.bundled

@Test func childAndGrandchildSessionsFoldIntoTheRootSession() throws {
  let turns = [
    sessionTurn("2026-10-07T09:00:00Z", sessionId: "ses_root"),
    sessionTurn("2026-10-07T09:10:00Z", sessionId: "ses_child", parent: "ses_root"),
    sessionTurn("2026-10-07T09:20:00Z", sessionId: "ses_grandchild", parent: "ses_child"),
    // The parent has no turn in the cycle, so the child keeps the parent id.
    sessionTurn("2026-10-08T09:00:00Z", sessionId: "ses_orphan", parent: "ses_gone"),
    sessionTurn("2026-10-08T10:00:00Z", sessionId: "ses_other"),
  ]
  let sessions = Credits.bySession(turns: turns, prices: sessionPrices) { _ in "runway-app" }
  #expect(Set(sessions.map(\.id)) == ["ses_root", "ses_gone", "ses_other"])
  #expect(sessions.first { $0.id == "ses_root" }?.turnCount == 3)
  let rootSession = try #require(sessions.first { $0.id == "ses_root" })
  #expect(rootSession.firstRecord == utcDate("2026-10-07T09:00:00Z"))
  #expect(rootSession.lastRecord == utcDate("2026-10-07T09:20:00Z"))
}

// Pi and omp ids never collide with each other, and turns without an id form one entry per source.
@Test func sessionsAreKeyedBySourceAndId() {
  let turns = [
    sessionTurn("2026-10-07T09:00:00Z", sessionId: "same", source: .pi),
    sessionTurn("2026-10-07T09:00:00Z", sessionId: "same", source: .omp),
    sessionTurn("2026-10-07T10:00:00Z", sessionId: nil, source: .pi),
    sessionTurn("2026-10-07T11:00:00Z", sessionId: nil, source: .pi),
  ]
  let sessions = Credits.bySession(turns: turns, prices: sessionPrices) { _ in "runway-app" }
  #expect(sessions.count == 3)
  #expect(sessions.first { $0.id == "" }?.turnCount == 2)
}

@Test func sessionTopModelAndBiggestTaskGoByCredits() throws {
  let debugCalls = [ToolCall(name: "edit", filePath: "a.swift"), ToolCall(name: "bash", command: "make"), ToolCall(name: "edit", filePath: "a.swift")]
  let turns = [
    sessionTurn("2026-10-07T09:00:00Z", sessionId: "s", source: .pi, model: "gemini-3.8-flash", output: 1_000_000, toolCalls: debugCalls),
    sessionTurn("2026-10-07T10:00:00Z", sessionId: "s", source: .pi, model: "gpt-6-luna", output: 10, toolCalls: [ToolCall(name: "read")]),
  ]
  let session = try #require(Credits.bySession(turns: turns, prices: sessionPrices) { _ in "runway-app" }.first)
  #expect(session.topModel == "gemini-3.8-flash")
  #expect(session.biggestTask == .debugging)
  #expect(session.label(locale: englishLocale) == "Oct 7 · Pi · Gemini 3.8 Flash · Debugging")
}

// With no price, the top model is the first id.
@Test func sessionWithOnlyUnpricedModelsTakesTheFirstModelId() throws {
  let turns = [
    sessionTurn("2026-10-07T09:00:00Z", sessionId: "s", model: "zeta-model"),
    sessionTurn("2026-10-07T10:00:00Z", sessionId: "s", model: "alpha-model"),
  ]
  let session = try #require(Credits.bySession(turns: turns, prices: sessionPrices) { _ in "x" }.first)
  #expect(session.topModel == "alpha-model")
  #expect(session.credits == 0)
}

@Test func byProjectMergesFoldersWithTheSameName() {
  let turns = [
    Turn(timestamp: fixtureCycleStart, source: .pi, records: [lunaRecord("2026-10-07T09:00:00Z")], directory: "/Users/example/www/acme/runway-app"),
    Turn(
      timestamp: fixtureCycleStart, source: .pi, records: [lunaRecord("2026-10-07T10:00:00Z", output: 1000)],
      directory: "/Users/example/orca/workspaces/runway-app/fix"
    ),
    Turn(timestamp: fixtureCycleStart, source: .pi, records: [lunaRecord("2026-10-07T11:00:00Z")], directory: "/Users/example/www/acme/billing-api"),
  ]
  let projectName = ProjectName.names(of: turns, homeDirectory: exampleHome) { _ in nil }
  let projects = Credits.byProject(turns: turns, prices: sessionPrices, projectName: projectName)
  #expect(projects.map(\.name) == ["runway-app", "billing-api"])
  let modelTotal = Credits.byModel(records: turns.flatMap(\.records), prices: sessionPrices).compactMap(\.credits).reduce(0, +)
  #expect(abs(projects.reduce(0) { $0 + $1.credits } - modelTotal) < 1e-12)
}

func spend(credits: Double, turnCount: Int = 9, first: String, last: String, biggestTaskCredits: Double = 0) -> SessionSpend {
  SessionSpend(
    id: "s", project: "runway-app", source: .opencode, turnCount: turnCount, credits: credits,
    firstRecord: utcDate(first), lastRecord: utcDate(last), topModel: "gpt-6.1-sol", biggestTask: .investigation,
    biggestTaskCredits: biggestTaskCredits
  )
}

// Days are UTC days: 23:30 UTC on Oct 14 and 01:00 UTC on Oct 15 are two days.
@Test func sessionLabelSpansDaysAndMonths() {
  #expect(spend(credits: 1, first: "2026-10-14T23:30:00Z", last: "2026-10-15T01:00:00Z").label(locale: englishLocale)
    == "Oct 14 to 15 · OpenCode · GPT-6.1 Sol · Investigation")
  #expect(spend(credits: 1, first: "2026-10-31T22:00:00Z", last: "2026-11-01T02:00:00Z").label(locale: englishLocale)
    == "Oct 31 to Nov 1 · OpenCode · GPT-6.1 Sol · Investigation")
  #expect(spend(credits: 1, first: "2026-10-07T00:00:00Z", last: "2026-10-07T23:59:00Z").label(locale: englishLocale)
    == "Oct 7 · OpenCode · GPT-6.1 Sol · Investigation")
}

@Test func topSessionSentenceAndShares() {
  let sessions = [
    spend(credits: 1_488.6, first: "2026-10-07T09:00:00Z", last: "2026-10-07T10:00:00Z", biggestTaskCredits: 612),
    spend(credits: 300, turnCount: 1, first: "2026-10-08T09:00:00Z", last: "2026-10-08T10:00:00Z"),
  ] + (1...5).map { _ in spend(credits: 100, first: "2026-10-09T09:00:00Z", last: "2026-10-09T10:00:00Z") }
  #expect(SessionSpend.topSentence(sessions, locale: englishLocale) == "The top session cost 1,489 credits in 9 turns, 41% of it investigation.")
  #expect(SessionSpend.topSentence([], locale: englishLocale) == nil)
  // The top 5: 1,488.6 + 300 + 3 * 100 of 2,288.6.
  #expect(SessionSpend.topShare(sessions, of: 2_288.6) == 91)
  #expect(sessions[0].sharePercentText(of: 12_546.59, locale: englishLocale) == "11.9%")
  #expect(sessions[0].sharePercentText(of: 0, locale: englishLocale) == "0.0%")
}

@Test(arguments: DemoScenario.Name.allCases)
func demoScenarioHasProjectsAndSessionsThatAddUp(name: DemoScenario.Name) {
  let sessionCredits = DemoScenario(name: name, now: demoNow).sessionCredits
  let modelTotal = sessionCredits.byModel.compactMap(\.credits).reduce(0, +)
  if name == .edgeEmpty {
    #expect(sessionCredits.byProject.isEmpty)
    #expect(sessionCredits.bySession.isEmpty)
    return
  }
  #expect(sessionCredits.byProject.count >= 2)
  #expect(sessionCredits.bySession.count >= SessionSpend.topCount)
  #expect(sessionCredits.byProject.first?.name == "runway-app")
  #expect(abs(sessionCredits.byProject.reduce(0) { $0 + $1.credits } - modelTotal) < 1e-9)
  #expect(abs(sessionCredits.bySession.reduce(0) { $0 + $1.credits } - modelTotal) < 1e-9)
}

@Test func manyModelsDemoFoldsProjectsIntoOther() {
  let projectCredits = DemoScenario(name: .manyModels, now: demoNow).sessionCredits.byProject
  #expect(projectCredits.count == 7)
  #expect(ProjectName.breakdown(projectCredits).items.last?.name == "Other projects")
}

func sessionSummaries(_ sessions: [SessionSpend]) -> [String] {
  sessions.map { "\($0.source.rawValue):\($0.id):\($0.turnCount)" }.sorted()
}

// ses_child_a has no message and ses_child_b only one before the cycle, so only the root and grandchild bill here.
@Test func descendantsFoldIntoTheRootWhenAnIntermediateSessionIsInactive() throws {
  let openCodeDirectory = try makeOpenCodeDataDirectory(fixture: "opencode/inactive-parent.sql")
  defer { try? FileManager.default.removeItem(at: openCodeDirectory) }
  let sessionCredits = SessionCredits.load(
    since: fixtureCycleStart, now: sessionCreditsNow, piDirectory: fixturesDirectory.appending(path: "missing/pi"),
    openCodeDirectory: openCodeDirectory, ompDirectory: fixturesDirectory.appending(path: "missing/omp"), priceURL: missingPriceURL
  )
  #expect(sessionSummaries(sessionCredits.bySession) == ["opencode:ses_root_a:2", "opencode:ses_root_b:2"])
  let modelTotal = sessionCredits.byModel.compactMap(\.credits).reduce(0, +)
  #expect(abs(sessionCredits.bySession.reduce(0) { $0 + $1.credits } - modelTotal) < 1e-9)
}

@Test func parentSessionsListsEveryParentEdgeWithoutUsage() throws {
  let openCodeDirectory = try makeOpenCodeDataDirectory(fixture: "opencode/inactive-parent.sql")
  defer { try? FileManager.default.removeItem(at: openCodeDirectory) }
  #expect(
    try OpenCodeSessionParser.parentSessions(inDirectory: openCodeDirectory)
      == ["ses_child_a": "ses_root_a", "ses_grand_a": "ses_child_a", "ses_child_b": "ses_root_b", "ses_grand_b": "ses_child_b"]
  )
}

@Test func openCodeParentsFoldSessionsWithoutTurns() {
  let turns = [
    sessionTurn("2026-10-07T09:00:00Z", sessionId: "root"),
    sessionTurn("2026-10-07T09:10:00Z", sessionId: "grandchild"),
  ]
  let parents = ["grandchild": "child", "child": "root"]
  #expect(sessionSummaries(Credits.bySession(turns: turns, prices: sessionPrices, openCodeParents: parents) { _ in "x" }) == ["opencode:root:2"])
}

// A database without session_v2, or with session_v2 but no parent_id, has no edges and no error.
@Test func partialSessionSchemasHaveNoParentEdgesOrFail() throws {
  let withoutSessionTable = try makeOpenCodeDataDirectory()
  let withoutParentColumn = try makeOpenCodeDataDirectory(fixture: "opencode/session-without-parent-id.sql")
  defer {
    try? FileManager.default.removeItem(at: withoutSessionTable)
    try? FileManager.default.removeItem(at: withoutParentColumn)
  }
  #expect(try OpenCodeSessionParser.parentSessions(inDirectory: withoutSessionTable).isEmpty)
  #expect(try OpenCodeSessionParser.parentSessions(inDirectory: withoutParentColumn).isEmpty)
  let turns = try OpenCodeSessionParser.turns(inDirectory: withoutParentColumn, since: fixtureCycleStart)
  #expect(turns.map(\.sessionId) == ["ses_root"])
  #expect(turns.allSatisfy { $0.parentSessionId == nil && $0.directory == nil && $0.projectRoot == nil })
}

// Without the project table the turns keep the folder and parent, and the project root is missing.
@Test func sessionTableWithoutProjectTableKeepsFolderAndParent() throws {
  let openCodeDirectory = try makeOpenCodeDataDirectory(fixture: "opencode/session-without-project.sql")
  defer { try? FileManager.default.removeItem(at: openCodeDirectory) }
  let turns = try OpenCodeSessionParser.turns(inDirectory: openCodeDirectory, since: fixtureCycleStart)
  let turnsBySession = Dictionary(uniqueKeysWithValues: turns.map { ($0.sessionId ?? "", $0) })
  #expect(turnsBySession["ses_child"]?.parentSessionId == "ses_root")
  #expect(turns.allSatisfy { $0.directory == "/Users/example/www/acme/runway-app" && $0.projectRoot == nil })
  #expect(try OpenCodeSessionParser.parentSessions(inDirectory: openCodeDirectory) == ["ses_child": "ses_root"])
}

// OpenCode has the edge same -> root. The Pi and omp sessions with those ids stay apart.
@Test func openCodeParentEdgesNeverMergePiOrOmpSessions() {
  let turns = [
    sessionTurn("2026-10-07T09:00:00Z", sessionId: "same", parent: "root"),
    sessionTurn("2026-10-07T09:10:00Z", sessionId: "root"),
    sessionTurn("2026-10-07T09:20:00Z", sessionId: "same", source: .pi),
    sessionTurn("2026-10-07T09:30:00Z", sessionId: "root", source: .pi),
    sessionTurn("2026-10-07T09:40:00Z", sessionId: "same", parent: "root", source: .omp),
    sessionTurn("2026-10-07T09:50:00Z", sessionId: "root", source: .omp),
  ]
  let expectedSummaries = ["omp:root:1", "omp:same:1", "opencode:root:2", "pi:root:1", "pi:same:1"]
  #expect(sessionSummaries(Credits.bySession(turns: turns, prices: sessionPrices) { _ in "x" }) == expectedSummaries)
  let parents = ["same": "root"]
  #expect(sessionSummaries(Credits.bySession(turns: turns, prices: sessionPrices, openCodeParents: parents) { _ in "x" }) == expectedSummaries)
}

@Test func selfParentSessionIsItsOwnRoot() {
  let turns = [sessionTurn("2026-10-07T09:00:00Z", sessionId: "a", parent: "a")]
  #expect(sessionSummaries(Credits.bySession(turns: turns, prices: sessionPrices) { _ in "x" }) == ["opencode:a:1"])
}

@Test func parentCycleFoldsIntoItsSmallestId() {
  let turns = [
    sessionTurn("2026-10-07T09:00:00Z", sessionId: "b", parent: "a"),
    sessionTurn("2026-10-07T09:10:00Z", sessionId: "a", parent: "b"),
  ]
  #expect(sessionSummaries(Credits.bySession(turns: turns, prices: sessionPrices) { _ in "x" }) == ["opencode:a:2"])
  #expect(sessionSummaries(Credits.bySession(turns: turns.reversed(), prices: sessionPrices) { _ in "x" }) == ["opencode:a:2"])
}

// d is a child of the cycle a -> b -> a, and c reaches it through d.
@Test func descendantsOfAParentCycleTakeTheCycleRoot() {
  let turns = [
    sessionTurn("2026-10-07T09:00:00Z", sessionId: "c", parent: "d"),
    sessionTurn("2026-10-07T09:10:00Z", sessionId: "d", parent: "b"),
    sessionTurn("2026-10-07T09:20:00Z", sessionId: "b", parent: "a"),
    sessionTurn("2026-10-07T09:30:00Z", sessionId: "a", parent: "b"),
  ]
  #expect(sessionSummaries(Credits.bySession(turns: turns, prices: sessionPrices) { _ in "x" }) == ["opencode:a:4"])
}

// Neither a nor the cycle member b is in the project lookup order, so the name must not follow the input order.
@Test func sessionRowsDoNotDependOnTheOrderOfTurns() {
  let turns = [
    sessionTurn("2026-10-07T09:00:00Z", sessionId: "d", parent: "b"),
    sessionTurn("2026-10-07T09:10:00Z", sessionId: "b", parent: "a"),
    sessionTurn("2026-10-07T09:20:00Z", sessionId: "e"),
  ] + [sessionTurn("2026-10-07T09:30:00Z", sessionId: "d2", parent: "d")]
  let parents = ["a": "b"]
  func rows(_ orderedTurns: [Turn]) -> [String] {
    Credits.bySession(turns: orderedTurns, prices: sessionPrices, openCodeParents: parents) { "project-\($0.sessionId ?? "")" }
      .map { "\($0.id):\($0.turnCount):\($0.project)" }
  }
  let expectedRows = rows(turns)
  #expect(expectedRows.contains("a:3:project-b"))
  for rotation in turns.indices {
    let rotatedTurns = Array(turns[rotation...] + turns[..<rotation])
    #expect(rows(rotatedTurns) == expectedRows)
    #expect(rows(rotatedTurns.reversed()) == expectedRows)
  }
}
