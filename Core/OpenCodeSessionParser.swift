import Foundation
import SQLite3

public enum OpenCodeReadError: Error, Equatable, Sendable {
  case cannotOpenDatabase
  case queryFailed
}

// OpenCode keeps sessions in SQLite. See Core/README.md for the tables and fields.
// The queries select only time, agent, model, token and tool call fields (tool name, file path,
// shell command), and the session folder, parent session and project root, so prompt and answer text
// and session titles never leave the database.
public enum OpenCodeSessionParser {
  public static let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".local/share/opencode")
  static let busyTimeoutMilliseconds: Int32 = 2_000
  static let copilotProvider = "github-copilot"

  // OpenCode 2.x table.
  static let currentTable = "session_message"

  // OpenCode 2.x rows that start or continue a turn, in session order. The session folder, parent session and project
  // root come from session_v2 and project when the database has them, and are NULL otherwise, as in older 2.x files.
  // LEFT JOIN, so a message without a session_v2 row still counts.
  static func turnQuery(hasSessionTable: Bool, hasProjectTable: Bool) -> String {
    let readsProject = hasSessionTable && hasProjectTable
    let sessionColumns = hasSessionTable ? "session.directory, session.parent_id" : "NULL, NULL"
    let sessionJoin = hasSessionTable ? "LEFT JOIN session_v2 AS session ON session.id = message.session_id" : ""
    let projectJoin = readsProject ? "LEFT JOIN project ON project.id = session.project_id" : ""
    return """
      SELECT message.id, message.session_id, message.type, message.time_created, json_extract(message.data, '$.agent'),
        json_extract(message.data, '$.model.providerID'), json_extract(message.data, '$.model.id'),
        json_extract(message.data, '$.tokens.input'), json_extract(message.data, '$.tokens.output'),
        json_extract(message.data, '$.tokens.reasoning'), json_extract(message.data, '$.tokens.cache.read'),
        json_extract(message.data, '$.tokens.cache.write'),
        \(sessionColumns), \(readsProject ? "project.worktree" : "NULL")
      FROM session_message AS message
        \(sessionJoin)
        \(projectJoin)
      WHERE message.time_created >= ?1
        AND message.type IN ('user', 'assistant')
      ORDER BY message.session_id, message.seq
      """
  }

  static let parentQuery = "SELECT id, parent_id FROM session_v2 WHERE parent_id IS NOT NULL"

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

  // OpenCode session ids with their parent id, for every session in session_v2 and not only those with usage in the
  // cycle, so a subagent still folds into its root when a session in between has no usage left. Reads ids only.
  public static func parentSessions(inDirectory directory: URL = dataDirectory) throws -> [String: String] {
    var parentBySession: [String: String] = [:]
    for databaseURL in databaseURLs(in: directory) {
      let database = try openDatabase(at: databaseURL)
      defer { sqlite3_close(database) }
      guard try columnsExist(["id", "parent_id"], in: "session_v2", database: database) else { continue }
      // The query has no parameter. forEachRow ignores the failed bind of the cycle start.
      try forEachRow(query: parentQuery, in: database, since: 0) { statement in
        guard let sessionId = text(statement, 0), let parentId = text(statement, 1) else { return }
        parentBySession[sessionId] = parentId
      }
    }
    return parentBySession
  }

  // Only turns with at least one Copilot record in the cycle. Reads the 2.x table only, see Core/README.md.
  // Rows before splitAt build their own turns, so the turns from splitAt on equal a read since splitAt.
  public static func turns(inDirectory directory: URL = dataDirectory, since cycleStart: Date, splitAt: Date? = nil) throws -> [Turn] {
    try databaseURLs(in: directory).flatMap { try turns(inDatabaseAt: $0, since: cycleStart, splitAt: splitAt) }
  }

  private static func databaseURLs(in directory: URL) -> [URL] {
    let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return fileNames
      .filter { $0.hasPrefix("opencode") && $0.hasSuffix(".db") }
      .map { directory.appending(path: $0) }
  }

  static func turns(inDatabaseAt databaseURL: URL, since cycleStart: Date, splitAt: Date? = nil) throws -> [Turn] {
    let database = try openDatabase(at: databaseURL)
    defer { sqlite3_close(database) }
    guard try tableExists(currentTable, in: database) else { return [] }
    let sessionTurnQuery = turnQuery(
      hasSessionTable: try columnsExist(["id", "directory", "parent_id", "project_id"], in: "session_v2", database: database),
      hasProjectTable: try columnsExist(["id", "worktree"], in: "project", database: database)
    )
    let cycleStartMilliseconds = Int64(cycleStart.timeIntervalSince1970 * 1000)

    var toolCallsByMessageId: [String: [ToolCall]] = [:]
    try forEachRow(query: toolCallQuery, in: database, since: cycleStartMilliseconds) { statement in
      guard let messageId = text(statement, 0), let name = text(statement, 1) else { return }
      toolCallsByMessageId[messageId, default: []].append(
        ToolCall(name: name, filePath: text(statement, 2), command: text(statement, 3))
      )
    }

    // Index 0 for rows from splitAt on, 1 for rows before it.
    var builders = [TurnBuilder(), TurnBuilder()]
    try forEachRow(query: sessionTurnQuery, in: database, since: cycleStartMilliseconds) { statement in
      guard let messageId = text(statement, 0), let sessionId = text(statement, 1), let type = text(statement, 2) else { return }
      let timestamp = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3)) / 1000)
      let isBeforeSplit = splitAt.map { timestamp < $0 } ?? false
      let session = TurnBuilder.Session(
        id: sessionId, directory: text(statement, 12), parentId: text(statement, 13), projectRoot: text(statement, 14)
      )
      builders[isBeforeSplit ? 1 : 0].add(session: session, type: type, timestamp: timestamp) { turn in
        turn.agent = turn.agent ?? text(statement, 4)
        turn.toolCalls += toolCallsByMessageId[messageId] ?? []
        if text(statement, 5) == copilotProvider, let model = text(statement, 6) {
          turn.records.append(UsageRecord(model: model, timestamp: timestamp, tokens: tokens(statement, firstColumn: 7)))
        }
      }
    }
    return builders.flatMap { $0.finishedTurns() }.filter { !$0.records.isEmpty }
  }

  // Groups rows in session order: a user row or a new session starts a turn.
  private struct TurnBuilder {
    struct Session {
      let id: String
      let directory: String?
      let parentId: String?
      let projectRoot: String?
    }

    private var turns: [Turn] = []
    private var currentTurn: Turn?
    private var currentSessionId: String?

    mutating func add(session: Session, type: String, timestamp: Date, addAssistant: (inout Turn) -> Void) {
      if session.id != currentSessionId || type == "user" {
        if let currentTurn { turns.append(currentTurn) }
        currentTurn = nil
        currentSessionId = session.id
      }
      var turn = currentTurn ?? Turn(
        timestamp: timestamp, source: .opencode, sessionId: session.id, directory: session.directory,
        projectRoot: session.projectRoot, parentSessionId: session.parentId
      )
      if type == "assistant" { addAssistant(&turn) }
      currentTurn = turn
    }

    func finishedTurns() -> [Turn] {
      turns + (currentTurn.map { [$0] } ?? [])
    }
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

  // False when the table is missing or lacks one of the columns.
  private static func columnsExist(_ columns: [String], in table: String, database: OpaquePointer?) throws -> Bool {
    var statement: OpaquePointer?
    let columnList = columns.map { "'\($0)'" }.joined(separator: ", ")
    let query = "SELECT count(*) FROM pragma_table_info('\(table)') WHERE name IN (\(columnList))"
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
      sqlite3_finalize(statement)
      throw OpenCodeReadError.queryFailed
    }
    defer { sqlite3_finalize(statement) }
    return sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == columns.count
  }
}
