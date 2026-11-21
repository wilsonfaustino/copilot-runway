@testable import Core
import Foundation
import Testing

// The fixture turns start at 01:00, 02:00, 03:00 and 04:00 UTC: a Portkey edit, a Copilot read with a Portkey grep, a
// Portkey answer with no tools, and an unpriced Portkey gh pr view.
private let portkeyTaskFixtures = fixturesDirectory.appending(path: "portkey-tasks")
private let expectedCategoriesByHour: [Int: TaskCategory] = [1: .implementation, 2: .investigation, 3: .uncategorized, 4: .review]

private func categoriesByHour(_ records: [PortkeyRecord]) -> [Int: TaskCategory] {
  Dictionary(uniqueKeysWithValues: records.map { (Runway.utcCalendar.component(.hour, from: $0.timestamp), $0.category) })
}

@Test func piPortkeyRecordsTakeTheCategoryOfTheirTurn() {
  var seenResponseIds = Set<String>()
  var portkeyRecords: [PortkeyRecord] = []
  let turns = PiSessionParser.turns(
    inDirectory: portkeyTaskFixtures, source: .pi, since: fixtureCycleStart, seenResponseIds: &seenResponseIds,
    portkeyRecords: &portkeyRecords
  ).turns
  #expect(categoriesByHour(portkeyRecords) == expectedCategoriesByHour)
  // Portkey-only turns are dropped after they are categorized. The mixed turn stays, with the category of its Portkey record.
  #expect(turns.map(TaskCategorizer.category(of:)) == [.investigation])
  #expect(turns.flatMap(\.records).map(\.model) == ["gpt-6-luna"])
}

@Test func openCodePortkeyRecordsTakeTheCategoryOfTheirTurn() throws {
  let dataDirectory = try makeOpenCodeDataDirectory(fixture: "portkey-tasks/opencode.sql")
  defer { try? FileManager.default.removeItem(at: dataDirectory) }
  let openCodeRead = try OpenCodeSessionParser.read(inDirectory: dataDirectory, since: fixtureCycleStart)
  #expect(categoriesByHour(openCodeRead.portkeyRecords) == expectedCategoriesByHour)
  #expect(openCodeRead.turns.map(TaskCategorizer.category(of:)) == [.investigation])
  #expect(openCodeRead.turns.flatMap(\.records).map(\.model) == ["gpt-6-luna"])
}

// Planning counts 1,000 Copilot output tokens or more. The first turn crosses the cycle start with 900 tokens before
// it and 200 after it, so only the records after it count, as for the Copilot turn. In the second turn a Portkey
// answer comes before a Portkey edit, and both get Implementation, the category of the whole turn. The third turn has
// no tools and 1,100 Copilot output tokens in the cycle, so its Copilot and Portkey records are both Planning.
@Test func sessionCreditsGivesPiPortkeyRecordsTheCategoryOfTheirTurnInTheCycle() throws {
  let jsonl = """
    {"type":"session","version":3,"id":"session-split","timestamp":"2026-10-09T23:00:00.000Z","cwd":"/p"}
    {"type":"message","id":"u1","message":{"role":"user","content":[],"timestamp":1791586800000}}
    {"type":"message","id":"a1","message":{"role":"assistant","content":[],"provider":"github-copilot","model":"gpt-6-luna",\
    "responseId":"resp_split_1","usage":{"input":10,"output":900,"cacheRead":0,"cacheWrite":0},"timestamp":1791586801000}}
    {"type":"message","id":"a2","message":{"role":"assistant","content":[],"provider":"github-copilot","model":"gpt-6-luna",\
    "responseId":"resp_split_2","usage":{"input":10,"output":200,"cacheRead":0,"cacheWrite":0},"timestamp":1791590401000}}
    {"type":"message","id":"a3","message":{"role":"assistant","content":[],"provider":"portkey","model":"deepseek-v4p1-flash",\
    "responseId":"resp_split_3","usage":{"input":10,"output":20,"cost":{"total":0.01}},"timestamp":1791590402000}}
    {"type":"message","id":"u2","message":{"role":"user","content":[],"timestamp":1791594000000}}
    {"type":"message","id":"a4","message":{"role":"assistant","content":[],"provider":"portkey","model":"deepseek-v4p1-flash",\
    "responseId":"resp_split_4","usage":{"input":10,"output":20,"cost":{"total":0.02}},"timestamp":1791594001000}}
    {"type":"message","id":"a5","message":{"role":"assistant","content":[{"type":"toolCall","id":"call_1","name":"edit",\
    "arguments":{"path":"a.swift"}}],"provider":"portkey","model":"deepseek-v4p1-flash","responseId":"resp_split_5",\
    "usage":{"input":10,"output":20,"cost":{"total":0.03}},"timestamp":1791594002000}}
    {"type":"message","id":"u3","message":{"role":"user","content":[],"timestamp":1791597600000}}
    {"type":"message","id":"a6","message":{"role":"assistant","content":[],"provider":"github-copilot","model":"gpt-6-luna",\
    "responseId":"resp_split_6","usage":{"input":10,"output":1100,"cacheRead":0,"cacheWrite":0},"timestamp":1791597601000}}
    {"type":"message","id":"a7","message":{"role":"assistant","content":[],"provider":"portkey","model":"deepseek-v4p1-flash",\
    "responseId":"resp_split_7","usage":{"input":10,"output":20,"cost":{"total":0.04}},"timestamp":1791597602000}}
    """
  let piDirectory = FileManager.default.temporaryDirectory.appending(path: "pi-split-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: piDirectory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: piDirectory) }
  try Data(jsonl.utf8).write(to: piDirectory.appending(path: "session-split.jsonl"))
  let cycleStart = utcDate("2026-10-10T00:00:00Z")
  let sessionCredits = SessionCredits.load(
    since: cycleStart,
    now: utcDate("2026-10-10T03:00:00Z"),
    piDirectory: piDirectory,
    openCodeDirectory: fixturesDirectory.appending(path: "missing"),
    ompDirectory: fixturesDirectory.appending(path: "missing/omp"),
    copilotDirectory: fixturesDirectory.appending(path: "missing/copilot"),
    priceURL: missingPriceURL
  )
  #expect(sessionCredits.portkey.records.map(\.category) == [.uncategorized, .implementation, .implementation, .planning])
  #expect(Set(sessionCredits.byCategory.map(\.category)) == [.uncategorized, .planning])
}

// OpenCode splits a turn that crosses splitAt into two turns, so each side keeps only its own tool calls. A
// Portkey-only plan agent turn with no tools is Planning.
@Test func openCodePortkeyRecordsAcrossTheSplitAndInThePlanAgent() throws {
  let dataDirectory = try makeOpenCodeDataDirectory(fixture: "portkey-tasks/opencode-split.sql")
  defer { try? FileManager.default.removeItem(at: dataDirectory) }
  let splitRead = try OpenCodeSessionParser.read(
    inDirectory: dataDirectory, since: fixtureCycleStart, splitAt: utcDate("2026-10-11T00:00:00Z")
  )
  #expect(splitRead.portkeyRecords.map(\.category) == [.investigation, .planning, .implementation])
  #expect(splitRead.turns.isEmpty)
}
