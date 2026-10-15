import Foundation
import SQLite3

public enum OpenCodeReadError: Error, Equatable, Sendable {
  case cannotOpenDatabase
  case queryFailed
}

// OpenCode keeps sessions in SQLite. See Core/README.md for the tables and fields.
// The queries select only model and token fields, so prompt text never leaves the database.
public enum OpenCodeSessionParser {
  public static let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".local/share/opencode")
  static let busyTimeoutMilliseconds: Int32 = 2_000

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

  public static func records(inDirectory directory: URL = dataDirectory, since cycleStart: Date) throws -> [UsageRecord] {
    let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    let databaseURLs = fileNames
      .filter { $0.hasPrefix("opencode") && $0.hasSuffix(".db") }
      .map { directory.appending(path: $0) }
    return try databaseURLs.flatMap { try records(inDatabaseAt: $0, since: cycleStart) }
  }

  // 2.x copies 1.x messages into session_message under the same id, so read legacy rows first
  // and add only the current rows with a new id.
  static func records(inDatabaseAt databaseURL: URL, since cycleStart: Date) throws -> [UsageRecord] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(database)
      throw OpenCodeReadError.cannotOpenDatabase
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, busyTimeoutMilliseconds)
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
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
      sqlite3_finalize(statement)
      throw OpenCodeReadError.queryFailed
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_int64(statement, 1, cycleStartMilliseconds)
    var rows: [(String, UsageRecord)] = []
    var stepResult = sqlite3_step(statement)
    while stepResult == SQLITE_ROW {
      if let messageIdText = sqlite3_column_text(statement, 0), let modelText = sqlite3_column_text(statement, 2) {
        let column = { (index: Int32) in Int(sqlite3_column_int64(statement, index)) }
        let tokens = TokenUsage(
          input: column(3),
          cachedInput: column(6),
          cacheWrite: column(7),
          // OpenCode stores reasoning apart from output. Both bill at the output rate.
          output: column(4) + column(5)
        )
        let timestamp = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 1)) / 1000)
        rows.append((String(cString: messageIdText), UsageRecord(model: String(cString: modelText), timestamp: timestamp, tokens: tokens)))
      }
      stepResult = sqlite3_step(statement)
    }
    guard stepResult == SQLITE_DONE else { throw OpenCodeReadError.queryFailed }
    return rows
  }
}
