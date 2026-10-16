import Core
import Foundation
import SQLite3
import Testing

let fixturesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")
let fixtureCycleStart = utcDate("2026-10-01T00:00:00Z")

@Test func piParserKeepsCopilotAssistantMessagesInCycle() {
  let piTurns = PiSessionParser.turns(inDirectory: fixturesDirectory.appending(path: "pi/sessions"), since: fixtureCycleStart)
  let records = piTurns.turns.flatMap(\.records).sorted { $0.timestamp < $1.timestamp }
  // One malformed line among good lines is skipped without a warning.
  #expect(!piTurns.hasUndecodableFile)
  // Skipped: user, tool result, other provider, before cycle, compaction, malformed line,
  // and resp_1 and resp_2 repeated in a fork and in a second file.
  #expect(records == [
    UsageRecord(
      model: "gpt-6.1-sol",
      timestamp: utcDate("2026-10-05T10:00:00Z"),
      tokens: TokenUsage(input: 100, cachedInput: 50000, cacheWrite: 1000, output: 2000)
    ),
    UsageRecord(
      model: "gpt-6-luna",
      timestamp: utcDate("2026-10-05T11:00:00Z"),
      tokens: TokenUsage(input: 10, cachedInput: 300000, cacheWrite: 200, output: 300)
    ),
    UsageRecord(
      model: "gpt-6-luna",
      timestamp: utcDate("2026-10-05T14:00:00Z"),
      tokens: TokenUsage(input: 0, cachedInput: 0, cacheWrite: 0, output: 7)
    ),
    UsageRecord(
      model: "gemini-3.8-flash",
      timestamp: utcDate("2026-10-06T09:00:00Z"),
      tokens: TokenUsage(input: 40, cachedInput: 0, cacheWrite: 0, output: 60)
    ),
  ])
}

@Test func piParserWithoutSessionsDirectoryReturnsNothing() {
  let missingDirectory = fixturesDirectory.appending(path: "missing")
  let piTurns = PiSessionParser.turns(inDirectory: missingDirectory, since: fixtureCycleStart)
  #expect(piTurns.turns.isEmpty)
  #expect(!piTurns.hasUndecodableFile)
}

// One file has lines but none decode, as after a Pi format change. The good file still counts.
@Test func piParserFlagsFileWithNoDecodableLine() {
  let piTurns = PiSessionParser.turns(inDirectory: fixturesDirectory.appending(path: "pi/undecodable"), since: fixtureCycleStart)
  #expect(piTurns.hasUndecodableFile)
  #expect(piTurns.turns.flatMap(\.records) == [
    UsageRecord(
      model: "gpt-6-luna",
      timestamp: utcDate("2026-10-05T12:00:00Z"),
      tokens: TokenUsage(input: 10, cachedInput: 0, cacheWrite: 0, output: 20)
    ),
  ])
}

@Test func openCodeParserKeepsCopilotAssistantMessagesInCycle() throws {
  let dataDirectory = try makeOpenCodeDataDirectory()
  defer { try? FileManager.default.removeItem(at: dataDirectory) }
  let records = try OpenCodeSessionParser.turns(inDirectory: dataDirectory, since: fixtureCycleStart)
    .flatMap(\.records)
    .sorted { $0.timestamp < $1.timestamp }
  // Skipped: user rows, other provider, before cycle, and the 1.x message table, which the parser does not read.
  // The legacy message copied into session_message counts once. Output includes reasoning tokens.
  #expect(records == [
    UsageRecord(
      model: "gpt-6.1-sol",
      timestamp: utcDate("2026-10-05T10:00:00Z"),
      tokens: TokenUsage(input: 100, cachedInput: 50000, cacheWrite: 0, output: 2500)
    ),
    UsageRecord(
      model: "gpt-6-luna",
      timestamp: utcDate("2026-10-05T11:00:00Z"),
      tokens: TokenUsage(input: 10, cachedInput: 300000, cacheWrite: 0, output: 340)
    ),
    UsageRecord(
      model: "gpt-6.1-sol",
      timestamp: utcDate("2026-10-05T14:00:00Z"),
      tokens: TokenUsage(input: 0, cachedInput: 0, cacheWrite: 0, output: 0)
    ),
  ])
}

@Test func openCodeParserWithoutDatabaseReturnsNothing() throws {
  let missingDirectory = fixturesDirectory.appending(path: "missing")
  #expect(try OpenCodeSessionParser.turns(inDirectory: missingDirectory, since: fixtureCycleStart).isEmpty)
}

// Builds opencode.db in a temporary folder from the SQL fixture, so the fixture stays plain text.
func makeOpenCodeDataDirectory(fixture: String = "opencode/opencode.sql") throws -> URL {
  let dataDirectory = FileManager.default.temporaryDirectory.appending(path: "opencode-fixture-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
  let fixtureSQL = try String(contentsOf: fixturesDirectory.appending(path: fixture), encoding: .utf8)
  var database: OpaquePointer?
  try #require(sqlite3_open(dataDirectory.appending(path: "opencode.db").path, &database) == SQLITE_OK)
  defer { sqlite3_close(database) }
  try #require(sqlite3_exec(database, fixtureSQL, nil, nil, nil) == SQLITE_OK)
  return dataDirectory
}
