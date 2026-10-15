import Foundation
import SQLite3

public enum OpenCodeReadError: Error, Equatable, Sendable {
  case cannotOpenDatabase
  case queryFailed
}

// OpenCode keeps sessions in SQLite. See Core/README.md for the tables and fields.
// The queries select only time, agent, model, token and tool call fields (tool name, file path,
// shell command), so prompt and answer text never leaves the database.
public enum OpenCodeSessionParser {
  public static let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".local/share/opencode")
  static let busyTimeoutMilliseconds: Int32 = 2_000
  static let copilotProvider = "github-copilot"

  // OpenCode 1.x table. 2.x stops writing it but keeps the old rows.
  static let legacyTable = "message"
  static let legacyQuery = """
    SELECT id, time_created, json_extract(data, '$.modelID'),
      json_extract(data, '$.tokens.input'), json_extract(data, '$.tokens.output'),
      json_extract(data, '$.tokens.reasoning'), json_extract(data, '$.tokens.cache.read'),
      json_extract(data, '$.tokens.cache.write')
    FROM message
    WHERE time_created >= ?1
      AND json_extract(data, '$.role') = 'assistant'
      AND json_extract(data, '$.providerID') = 'github-copilot'
    """

  // OpenCode 2.x table.
  static let currentTable = "session_message"
  static let currentQuery = """
    SELECT id, time_created, json_extract(data, '$.model.id'),
      json_extract(data, '$.tokens.input'), json_extract(data, '$.tokens.output'),
      json_extract(data, '$.tokens.reasoning'), json_extract(data, '$.tokens.cache.read'),
      json_extract(data, '$.tokens.cache.write')
    FROM session_message
    WHERE time_created >= ?1
      AND type = 'assistant'
      AND json_extract(data, '$.model.providerID') = 'github-copilot'
    """

  // OpenCode 2.x rows that start or continue a turn, in session order.
  static let turnQuery = """
    SELECT id, session_id, type, time_created, json_extract(data, '$.agent'),
      json_extract(data, '$.model.providerID'), json_extract(data, '$.model.id'),
      json_extract(data, '$.tokens.input'), json_extract(data, '$.tokens.output'),
      json_extract(data, '$.tokens.reasoning'), json_extract(data, '$.tokens.cache.read'),
      json_extract(data, '$.tokens.cache.write')
    FROM session_message
    WHERE time_created >= ?1
      AND type IN ('user', 'assistant')
    ORDER BY session_id, seq
    """

  // One row per tool call, or one row per file for patch tools that list their files in metadata.
  static let toolCallQuery = """
    SELECT message.id, json_extract(tool.value, '$.name'),
      coalesce(json_extract(patchFile.value, '$.file'), json_extract(tool.value, '$.state.input.path'),
        json_extract(tool.value, '$.state.input.filePath')),
      json_extract(tool.value, '$.state.input.command')
    FROM session_message AS message
      JOIN json_each(message.data, '$.content') AS tool
      LEFT JOIN json_each(json_extract(tool.value, '$.state.metadata.files')) AS patchFile
    WHERE message.time_created >= ?1
      AND message.type = 'assistant'
      AND json_extract(tool.value, '$.type') = 'tool'
    ORDER BY message.id, tool.key, patchFile.key
    """

  public static func records(inDirectory directory: URL = dataDirectory, since cycleStart: Date) throws -> [UsageRecord] {
    try databaseURLs(in: directory).flatMap { try records(inDatabaseAt: $0, since: cycleStart) }
  }

  // Only turns with at least one Copilot record in the cycle. Reads the 2.x table only, see Core/README.md.
  public static func turns(inDirectory directory: URL = dataDirectory, since cycleStart: Date) throws -> [Turn] {
    try databaseURLs(in: directory).flatMap { try turns(inDatabaseAt: $0, since: cycleStart) }
  }

  private static func databaseURLs(in directory: URL) -> [URL] {
    let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return fileNames
      .filter { $0.hasPrefix("opencode") && $0.hasSuffix(".db") }
      .map { directory.appending(path: $0) }
  }

  // 2.x copies 1.x messages into session_message under the same id, so read legacy rows first
  // and add only the current rows with a new id.
  static func records(inDatabaseAt databaseURL: URL, since cycleStart: Date) throws -> [UsageRecord] {
    let database = try openDatabase(at: databaseURL)
    defer { sqlite3_close(database) }
    let cycleStartMilliseconds = Int64(cycleStart.timeIntervalSince1970 * 1000)
    var seenMessageIds = Set<String>()
    var records: [UsageRecord] = []
    for (table, query) in [(legacyTable, legacyQuery), (currentTable, currentQuery)] {
      guard try tableExists(table, in: database) else { continue }
      for (messageId, record) in try rows(query: query, in: database, since: cycleStartMilliseconds)
      where seenMessageIds.insert(messageId).inserted {
        records.append(record)
      }
    }
    return records
  }

  static func turns(inDatabaseAt databaseURL: URL, since cycleStart: Date) throws -> [Turn] {
    let database = try openDatabase(at: databaseURL)
    defer { sqlite3_close(database) }
    guard try tableExists(currentTable, in: database) else { return [] }
    let cycleStartMilliseconds = Int64(cycleStart.timeIntervalSince1970 * 1000)

    var toolCallsByMessageId: [String: [ToolCall]] = [:]
    try forEachRow(query: toolCallQuery, in: database, since: cycleStartMilliseconds) { statement in
      guard let messageId = text(statement, 0), let name = text(statement, 1) else { return }
      toolCallsByMessageId[messageId, default: []].append(
        ToolCall(name: name, filePath: text(statement, 2), command: text(statement, 3))
      )
    }

    var turns: [Turn] = []
    var currentTurn: Turn?
    var currentSessionId: String?
    try forEachRow(query: turnQuery, in: database, since: cycleStartMilliseconds) { statement in
      guard let messageId = text(statement, 0), let sessionId = text(statement, 1), let type = text(statement, 2) else { return }
      let timestamp = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3)) / 1000)
      if sessionId != currentSessionId || type == "user" {
        if let currentTurn { turns.append(currentTurn) }
        currentTurn = nil
        currentSessionId = sessionId
      }
      var turn = currentTurn ?? Turn(timestamp: timestamp, source: .opencode)
      if type == "assistant" {
        turn.agent = turn.agent ?? text(statement, 4)
        turn.toolCalls += toolCallsByMessageId[messageId] ?? []
        if text(statement, 5) == copilotProvider, let model = text(statement, 6) {
          turn.records.append(UsageRecord(model: model, timestamp: timestamp, tokens: tokens(statement, firstColumn: 7)))
        }
      }
      currentTurn = turn
    }
    if let currentTurn { turns.append(currentTurn) }
    return turns.filter { !$0.records.isEmpty }
  }

  private static func openDatabase(at databaseURL: URL) throws -> OpaquePointer? {
    var database: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(database)
      throw OpenCodeReadError.cannotOpenDatabase
    }
    sqlite3_busy_timeout(database, busyTimeoutMilliseconds)
    return database
  }

  private static func forEachRow(query: String, in database: OpaquePointer?, since cycleStartMilliseconds: Int64, body: (OpaquePointer?) -> Void) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
      sqlite3_finalize(statement)
      throw OpenCodeReadError.queryFailed
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_int64(statement, 1, cycleStartMilliseconds)
    var stepResult = sqlite3_step(statement)
    while stepResult == SQLITE_ROW {
      body(statement)
      stepResult = sqlite3_step(statement)
    }
    guard stepResult == SQLITE_DONE else { throw OpenCodeReadError.queryFailed }
  }

  private static func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    sqlite3_column_text(statement, index).map { String(cString: $0) }
  }

  // Columns in order: input, output, reasoning, cache read, cache write.
  private static func tokens(_ statement: OpaquePointer?, firstColumn: Int32) -> TokenUsage {
    let column = { (offset: Int32) in Int(sqlite3_column_int64(statement, firstColumn + offset)) }
    return TokenUsage(
      input: column(0),
      cachedInput: column(3),
      cacheWrite: column(4),
      // OpenCode stores reasoning apart from output. Both bill at the output rate.
      output: column(1) + column(2)
    )
  }

  private static func tableExists(_ table: String, in database: OpaquePointer?) throws -> Bool {
    var statement: OpaquePointer?
    let query = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(table)'"
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
      sqlite3_finalize(statement)
      throw OpenCodeReadError.queryFailed
    }
    defer { sqlite3_finalize(statement) }
    return sqlite3_step(statement) == SQLITE_ROW
  }

  private static func rows(query: String, in database: OpaquePointer?, since cycleStartMilliseconds: Int64) throws -> [(String, UsageRecord)] {
    var rows: [(String, UsageRecord)] = []
    try forEachRow(query: query, in: database, since: cycleStartMilliseconds) { statement in
      guard let messageId = text(statement, 0), let model = text(statement, 2) else { return }
      let timestamp = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 1)) / 1000)
      rows.append((messageId, UsageRecord(model: model, timestamp: timestamp, tokens: tokens(statement, firstColumn: 3))))
    }
    return rows
  }
}
