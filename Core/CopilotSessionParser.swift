import Foundation

// The Copilot CLI and the GitHub Copilot desktop app write one folder per session, with events.jsonl and
// workspace.yaml, in the same format. See Core/README.md.
public enum CopilotSessionParser {
  public static let sessionStateDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".copilot/session-state")
  static let copilotProvider = "copilot"
  // 1 credit = $0.01 = 1e9 nano AIU. CLI sessions give the same credits as PriceTable with this rate.
  static let nanoAiuPerCredit = 1e9
  // Other clients (hermes-agent, vscode-agent-host) and folders without workspace.yaml are skipped.
  static let sourcesByClientName: [String: SessionSource] = ["github/cli": .copilotCli, "github/autopilot": .copilotApp]

  // Only turns with at least one Copilot record in the cycle, so every record is in exactly one turn.
  // hasUndecodableFile is true when an events file has lines but none of them decode, for example after a format change.
  public static func turns(
    inDirectory directory: URL = sessionStateDirectory,
    since cycleStart: Date
  ) -> (turns: [Turn], hasUndecodableFile: Bool) {
    guard let sessionFolders = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    else { return ([], false) }
    var seenUsageIds = Set<String>()
    var allTurns: [Turn] = []
    var hasUndecodableFile = false
    // Sorted, so a usage id in two folders always counts for the same folder.
    for folder in sessionFolders.sorted(by: { $0.path < $1.path }) {
      guard let workspace = try? String(contentsOf: folder.appending(path: "workspace.yaml"), encoding: .utf8),
        let clientName = value(of: "client_name", inYAML: workspace),
        let source = sourcesByClientName[clientName]
      else { continue }
      let eventsURL = folder.appending(path: "events.jsonl")
      let modificationDate = (try? eventsURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      // A file last written before the cycle cannot hold messages from this cycle.
      if let modificationDate, modificationDate < cycleStart { continue }
      guard let fileData = try? Data(contentsOf: eventsURL) else { continue }
      guard let fileTurns = turns(
        fromJSONL: fileData,
        source: source,
        sessionId: value(of: "id", inYAML: workspace) ?? folder.lastPathComponent,
        directory: value(of: "cwd", inYAML: workspace),
        since: cycleStart,
        seenUsageIds: &seenUsageIds
      ) else {
        hasUndecodableFile = true
        continue
      }
      allTurns += fileTurns
    }
    return (allTurns, hasUndecodableFile)
  }

  // A resumed session can repeat a usage record, so records are deduplicated by accounting.usageId.
  // A single bad line is skipped, because the client can be writing the last line. nil when the file has lines but none decode.
  static func turns(
    fromJSONL fileData: Data,
    source: SessionSource,
    sessionId: String?,
    directory: String?,
    since cycleStart: Date,
    seenUsageIds: inout Set<String>
  ) -> [Turn]? {
    let decoder = JSONDecoder()
    let timestampParser = TimestampParser()
    let lines = fileData.split(separator: UInt8(ascii: "\n"))
    var decodedLineCount = 0
    var turns: [Turn] = []
    // The toolCallId of each tool call in turns, in the same order, so fileEdits can fill in apply_patch paths.
    var toolCallIds: [[String?]] = []
    var editedPathsByToolCallId: [String: [String]] = [:]
    for line in lines {
      guard let header = try? decoder.decode(EventHeader.self, from: Data(line)) else { continue }
      decodedLineCount += 1
      switch header.type {
      case "user.message":
        guard let timestamp = timestampParser.date(from: header.timestamp) else { continue }
        turns.append(Turn(timestamp: timestamp, source: source))
        toolCallIds.append([])
      case "session.usage_record":
        guard let timestamp = timestampParser.date(from: header.timestamp),
          let usage = try? decoder.decode(Event<UsageData>.self, from: Data(line)).data.usage,
          let record = record(from: usage, timestamp: timestamp, since: cycleStart, seenUsageIds: &seenUsageIds)
        else { continue }
        if turns.isEmpty {
          turns.append(Turn(timestamp: timestamp, source: source))
          toolCallIds.append([])
        }
        turns[turns.count - 1].records.append(record)
      case "assistant.message":
        guard let toolRequests = try? decoder.decode(Event<MessageData>.self, from: Data(line)).data.toolRequests,
          !turns.isEmpty
        else { continue }
        turns[turns.count - 1].toolCalls += toolRequests.map(\.toolCall)
        toolCallIds[turns.count - 1] += toolRequests.map(\.toolCallId)
      case "tool.execution_complete":
        guard let completion = try? decoder.decode(Event<CompletionData>.self, from: Data(line)).data,
          let toolCallId = completion.toolCallId, let fileEdits = completion.fileEdits
        else { continue }
        editedPathsByToolCallId[toolCallId, default: []] += fileEdits.compactMap(\.path)
      default:
        continue
      }
    }
    if !lines.isEmpty && decodedLineCount == 0 { return nil }
    return turns.indices.compactMap { turnIndex in
      guard !turns[turnIndex].records.isEmpty else { return nil }
      var sessionTurn = turns[turnIndex]
      sessionTurn.toolCalls = expandedToolCalls(
        turns[turnIndex].toolCalls, toolCallIds: toolCallIds[turnIndex], editedPathsByToolCallId: editedPathsByToolCallId)
      sessionTurn.sessionId = sessionId
      sessionTurn.directory = directory
      return sessionTurn
    }
  }

  private static func expandedToolCalls(
    _ toolCalls: [ToolCall], toolCallIds: [String?], editedPathsByToolCallId: [String: [String]]
  ) -> [ToolCall] {
    zip(toolCalls, toolCallIds).flatMap { toolCall, toolCallId in
      guard toolCall.filePath == nil, let toolCallId, let editedPaths = editedPathsByToolCallId[toolCallId], !editedPaths.isEmpty
      else { return [toolCall] }
      return editedPaths.map { ToolCall(name: toolCall.name, filePath: $0) }
    }
  }

  private static func record(from usage: Usage, timestamp: Date, since cycleStart: Date, seenUsageIds: inout Set<String>) -> UsageRecord? {
    guard
      usage.provider?.id == copilotProvider,
      usage.isByok == false,
      let model = usage.model,
      timestamp >= cycleStart
    else { return nil }
    if let usageId = usage.accounting?.usageId {
      guard seenUsageIds.insert(usageId).inserted else { return nil }
    }
    let cacheRead = usage.cacheReadTokens ?? 0
    let cacheWrite = usage.cacheWriteTokens ?? 0
    let tokens = TokenUsage(
      // inputTokens includes cache reads and writes.
      input: max((usage.inputTokens ?? 0) - cacheRead - cacheWrite, 0),
      cachedInput: cacheRead,
      cacheWrite: cacheWrite,
      // outputTokens already includes reasoningTokens.
      output: usage.outputTokens ?? 0
    )
    let billedCredits = usage.copilotUsage?.totalNanoAiu.map { $0 / nanoAiuPerCredit }
    return UsageRecord(model: model, timestamp: timestamp, tokens: tokens, billedCredits: billedCredits)
  }

  // workspace.yaml is flat "key: value" lines. Only top level scalar values are read.
  static func value(of key: String, inYAML yaml: String) -> String? {
    for line in yaml.split(whereSeparator: \.isNewline) where line.hasPrefix("\(key):") {
      let value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
      let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      return unquoted.isEmpty ? nil : unquoted
    }
    return nil
  }

  // Accepts fractional or whole seconds. One instance per parse, so the formatters are made once and not once per line.
  private struct TimestampParser {
    private let fractionalFormatter = ISO8601DateFormatter()
    private let wholeSecondFormatter = ISO8601DateFormatter()

    init() {
      fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      wholeSecondFormatter.formatOptions = [.withInternetDateTime]
    }

    func date(from text: String?) -> Date? {
      guard let text else { return nil }
      return fractionalFormatter.date(from: text) ?? wholeSecondFormatter.date(from: text)
    }
  }

  private struct EventHeader: Decodable {
    let type: String
    let timestamp: String?
  }

  private struct Event<EventData: Decodable>: Decodable {
    let data: EventData
  }

  private struct UsageData: Decodable {
    let usage: Usage
  }

  private struct Usage: Decodable {
    let model: String?
    let provider: Provider?
    let isByok: Bool?
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?
    let accounting: Accounting?
    let copilotUsage: CopilotUsage?
  }

  private struct Provider: Decodable {
    let id: String?
  }

  private struct Accounting: Decodable {
    let usageId: String?
  }

  private struct CopilotUsage: Decodable {
    let totalNanoAiu: Double?
  }

  // Only the tool requests. Message text is never decoded.
  private struct MessageData: Decodable {
    let toolRequests: [ToolRequest]
  }

  private struct ToolRequest: Decodable {
    let toolCallId: String?
    let name: String
    let arguments: Arguments?

    enum CodingKeys: String, CodingKey {
      case toolCallId, name, arguments
    }

    // apply_patch is a custom tool whose arguments are the patch text, not an object, so they are ignored.
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
      name = try container.decode(String.self, forKey: .name)
      arguments = try? container.decodeIfPresent(Arguments.self, forKey: .arguments)
    }

    var toolCall: ToolCall {
      ToolCall(name: name, filePath: arguments?.path, command: arguments?.command)
    }
  }

  private struct Arguments: Decodable {
    let path: String?
    let command: String?

    enum CodingKeys: String, CodingKey {
      case path, command
    }

    // Other tools reuse these keys with other types, so a value that is not a string is ignored.
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try? container.decodeIfPresent(String.self, forKey: .path)
      command = try? container.decodeIfPresent(String.self, forKey: .command)
    }
  }

  private struct CompletionData: Decodable {
    let toolCallId: String?
    let fileEdits: [FileEdit]?
  }

  private struct FileEdit: Decodable {
    let path: String?
  }
}
