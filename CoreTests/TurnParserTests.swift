import Core
import Foundation
import Testing

let turnFixturesDirectory = fixturesDirectory.appending(path: "turns")

func lunaRecord(_ isoString: String, output: Int = 10) -> UsageRecord {
  UsageRecord(
    model: "gpt-6-luna",
    timestamp: utcDate(isoString),
    tokens: TokenUsage(input: 100, cachedInput: 0, cacheWrite: 0, output: output)
  )
}

@Test func piTurnsGroupMessagesUntilTheNextUserMessage() {
  let turns = PiSessionParser.turns(inDirectory: turnFixturesDirectory.appending(path: "pi-grouping"), since: fixtureCycleStart).turns
  // Dropped: the turn with only another provider. Skipped: the message before the cycle.
  #expect(turns == [
    Turn(
      timestamp: utcDate("2026-10-07T00:30:00Z"),
      source: .pi,
      toolCalls: [ToolCall(name: "read", filePath: "Sources/a.swift")],
      records: [lunaRecord("2026-10-07T00:30:00Z")],
      sessionId: "session-fixture",
      directory: "/Users/example/project"
    ),
    Turn(
      timestamp: utcDate("2026-10-07T01:00:00Z"),
      source: .pi,
      toolCalls: [
        ToolCall(name: "bash", command: "make"),
        ToolCall(name: "edit", filePath: "Sources/a.swift"),
        ToolCall(name: "read", filePath: "Sources/b.swift"),
      ],
      records: [lunaRecord("2026-10-07T01:00:01Z"), lunaRecord("2026-10-07T01:00:03Z")],
      sessionId: "session-fixture",
      directory: "/Users/example/project"
    ),
    Turn(
      timestamp: utcDate("2026-09-30T23:00:00Z"),
      source: .pi,
      toolCalls: [ToolCall(name: "read", filePath: "Sources/d.swift")],
      records: [lunaRecord("2026-10-01T00:10:00Z")],
      sessionId: "session-fixture",
      directory: "/Users/example/project"
    ),
  ])
}

@Test func openCodeTurnsFollowSessionOrderAndSplitPatchFiles() throws {
  let dataDirectory = try makeOpenCodeDataDirectory(fixture: "turns/opencode.sql")
  defer { try? FileManager.default.removeItem(at: dataDirectory) }
  let turns = try OpenCodeSessionParser.turns(inDirectory: dataDirectory, since: fixtureCycleStart)
  // Dropped: the turn with only another provider and the turn before the cycle.
  #expect(turns.map(\.timestamp) == (1...7).map { utcDate("2026-10-07T0\($0):00:00Z") })
  #expect(turns.map(\.agent) == ["plan", "plan", "build", "build", "build", "build", "general"])
  #expect(turns.allSatisfy { $0.source == .opencode })
  // The synthetic row between the messages does not start a turn.
  #expect(turns[2].toolCalls == [
    ToolCall(name: "patch", filePath: "/p/a.swift"),
    ToolCall(name: "patch", filePath: "/p/b.swift"),
    ToolCall(name: "shell", command: "swift test"),
    ToolCall(name: "edit", filePath: "/p/b.swift"),
  ])
  #expect(turns[2].records.count == 3)
  #expect(turns[6].toolCalls == [ToolCall(name: "patch")])
}
