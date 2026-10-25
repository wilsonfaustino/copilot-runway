import Foundation

// Pi and omp write one JSONL file per session, in the same format. See Core/README.md.
public enum PiSessionParser {
  public static let sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".pi/agent/sessions")
  public static let ompSessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".omp/agent/sessions")
  static let copilotProvider = "github-copilot"

  // Only turns with at least one Copilot record in the cycle, so every record is in exactly one turn.
  // hasUndecodableFile is true when a file has lines but none of them decode, for example after a format change.
  public static func turns(
    inDirectory directory: URL = sessionsDirectory,
    source: SessionSource = .pi,
    since cycleStart: Date
  ) -> (turns: [Turn], hasUndecodableFile: Bool) {
    var seenResponseIds = Set<String>()
    return turns(inDirectory: directory, source: source, since: cycleStart, seenResponseIds: &seenResponseIds)
  }

  // seenResponseIds is shared across calls, so a response in more than one root counts once, for the first root read.
  public static func turns(
    inDirectory directory: URL,
    source: SessionSource,
    since cycleStart: Date,
    seenResponseIds: inout Set<String>
  ) -> (turns: [Turn], hasUndecodableFile: Bool) {
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey]
    ) else { return ([], false) }
    var allTurns: [Turn] = []
    var hasUndecodableFile = false
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
      let modificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      // A file last written before the cycle cannot hold messages from this cycle.
      if let modificationDate, modificationDate < cycleStart { continue }
      guard let fileData = try? Data(contentsOf: fileURL) else { continue }
      guard let fileTurns = turns(fromJSONL: fileData, source: source, since: cycleStart, seenResponseIds: &seenResponseIds) else {
        hasUndecodableFile = true
        continue
      }
      allTurns += fileTurns
    }
    return (allTurns, hasUndecodableFile)
  }

  // Forked sessions copy earlier entries, so the same response can appear in more than one file.
  // A single bad line is skipped, because Pi can be writing the last line. nil when the file has lines but none decode.
  static func turns(
    fromJSONL fileData: Data,
    source: SessionSource,
    since cycleStart: Date,
    seenResponseIds: inout Set<String>
  ) -> [Turn]? {
    let decoder = JSONDecoder()
    let lines = fileData.split(separator: UInt8(ascii: "\n"))
    var decodedLineCount = 0
    var turns: [Turn] = []
    var currentTurn: Turn?
    var header: SessionHeader?
    for line in lines {
      guard let entry = try? decoder.decode(Entry.self, from: Data(line)) else { continue }
      decodedLineCount += 1
      // omp writes a title entry before the header, so the header is the first session entry, not the first line.
      if entry.type == "session", header == nil {
        header = try? decoder.decode(SessionHeader.self, from: Data(line))
      }
      guard entry.type == "message", let message = entry.message else { continue }
      switch message.role {
      case "user":
        if let currentTurn { turns.append(currentTurn) }
        currentTurn = Turn(timestamp: date(milliseconds: message.timestamp ?? 0), source: source)
      case "assistant":
        var turn = currentTurn ?? Turn(timestamp: date(milliseconds: message.timestamp ?? 0), source: source)
        turn.toolCalls += message.toolCalls
        if let record = record(from: message, since: cycleStart, seenResponseIds: &seenResponseIds) {
          turn.records.append(record)
        }
        currentTurn = turn
      default:
        continue
      }
    }
    if !lines.isEmpty && decodedLineCount == 0 { return nil }
    if let currentTurn { turns.append(currentTurn) }
    return turns.filter { !$0.records.isEmpty }.map { turn in
      var sessionTurn = turn
      sessionTurn.sessionId = header?.id
      sessionTurn.directory = header?.cwd
      return sessionTurn
    }
  }

  private static func record(from message: Message, since cycleStart: Date, seenResponseIds: inout Set<String>) -> UsageRecord? {
    guard
      message.provider == copilotProvider,
      let model = message.model,
      let usage = message.usage,
      let timestampMilliseconds = message.timestamp
    else { return nil }
    let timestamp = date(milliseconds: timestampMilliseconds)
    guard timestamp >= cycleStart else { return nil }
    if let responseId = message.responseId {
      guard seenResponseIds.insert(responseId).inserted else { return nil }
    }
    let tokens = TokenUsage(
      input: usage.input ?? 0,
      cachedInput: usage.cacheRead ?? 0,
      cacheWrite: usage.cacheWrite ?? 0,
      // Pi output already counts reasoning tokens: totalTokens = input + output + cacheRead + cacheWrite.
      output: usage.output ?? 0
    )
    return UsageRecord(model: model, timestamp: timestamp, tokens: tokens)
  }

  private static func date(milliseconds: Double) -> Date {
    Date(timeIntervalSince1970: milliseconds / 1000)
  }

  private struct Entry: Decodable {
    let type: String
    let message: Message?
  }

  // The first line of a session file. Its other fields (version, timestamp) are not read.
  private struct SessionHeader: Decodable {
    let id: String?
    let cwd: String?
  }

  private struct Message: Decodable {
    let role: String
    let provider: String?
    let model: String?
    let responseId: String?
    let timestamp: Double?
    let usage: Usage?
    let toolCalls: [ToolCall]

    enum CodingKeys: String, CodingKey {
      case role, provider, model, responseId, timestamp, usage, content
    }

    // Content shapes vary by role. A content array that does not decode loses its tool calls, never the usage.
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      role = try container.decode(String.self, forKey: .role)
      provider = try container.decodeIfPresent(String.self, forKey: .provider)
      model = try container.decodeIfPresent(String.self, forKey: .model)
      responseId = try container.decodeIfPresent(String.self, forKey: .responseId)
      timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
      usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
      let content = (try? container.decodeIfPresent([ContentItem].self, forKey: .content)) ?? []
      toolCalls = content.compactMap { item in
        guard item.type == "toolCall", let name = item.name else { return nil }
        return ToolCall(name: name, filePath: item.arguments?.filePath, command: item.arguments?.command)
      }
    }
  }

  // Only the tool name, path and command. Message text is never decoded.
  private struct ContentItem: Decodable {
    let type: String?
    let name: String?
    let arguments: Arguments?
  }

  private struct Arguments: Decodable {
    let path: String?
    let command: String?
    // The omp edit tool has no path. Its input starts with a "[<path>#<hash>]" header.
    let input: String?

    enum CodingKeys: String, CodingKey {
      case path, command, input
    }

    // input is free form in other tools, so a value that is not a string is ignored.
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try container.decodeIfPresent(String.self, forKey: .path)
      command = try container.decodeIfPresent(String.self, forKey: .command)
      input = try? container.decodeIfPresent(String.self, forKey: .input)
    }

    var filePath: String? {
      if let path { return path }
      guard let input, input.hasPrefix("["), let firstLine = input.split(separator: "\n").first,
            let hashIndex = firstLine.firstIndex(of: "#")
      else { return nil }
      return String(firstLine[firstLine.index(after: firstLine.startIndex)..<hashIndex])
    }
  }

  private struct Usage: Decodable {
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
  }
}
