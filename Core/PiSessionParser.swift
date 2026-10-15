import Foundation

// Pi writes one JSONL file per session. See Core/README.md for the format.
public enum PiSessionParser {
  public static let sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".pi/agent/sessions")
  static let copilotProvider = "github-copilot"

  public static func records(inDirectory directory: URL = sessionsDirectory, since cycleStart: Date) -> [UsageRecord] {
    turns(inDirectory: directory, since: cycleStart).flatMap(\.records)
  }

  // Only turns with at least one Copilot record in the cycle, so every record is in exactly one turn.
  public static func turns(inDirectory directory: URL = sessionsDirectory, since cycleStart: Date) -> [Turn] {
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey]
    ) else { return [] }
    var seenResponseIds = Set<String>()
    var allTurns: [Turn] = []
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
      let modificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      // A file last written before the cycle cannot hold messages from this cycle.
      if let modificationDate, modificationDate < cycleStart { continue }
      guard let fileData = try? Data(contentsOf: fileURL) else { continue }
      allTurns += turns(fromJSONL: fileData, since: cycleStart, seenResponseIds: &seenResponseIds)
    }
    return allTurns
  }

  // Forked sessions copy earlier entries, so the same response can appear in more than one file.
  static func turns(fromJSONL fileData: Data, since cycleStart: Date, seenResponseIds: inout Set<String>) -> [Turn] {
    let decoder = JSONDecoder()
    var turns: [Turn] = []
    var currentTurn: Turn?
    for line in fileData.split(separator: UInt8(ascii: "\n")) {
      guard
        let entry = try? decoder.decode(Entry.self, from: Data(line)),
        entry.type == "message",
        let message = entry.message
      else { continue }
      switch message.role {
      case "user":
        if let currentTurn { turns.append(currentTurn) }
        currentTurn = Turn(timestamp: date(milliseconds: message.timestamp ?? 0), source: .pi)
      case "assistant":
        var turn = currentTurn ?? Turn(timestamp: date(milliseconds: message.timestamp ?? 0), source: .pi)
        turn.toolCalls += message.toolCalls
        if let record = record(from: message, since: cycleStart, seenResponseIds: &seenResponseIds) {
          turn.records.append(record)
        }
        currentTurn = turn
      default:
        continue
      }
    }
    if let currentTurn { turns.append(currentTurn) }
    return turns.filter { !$0.records.isEmpty }
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
        return ToolCall(name: name, filePath: item.arguments?.path, command: item.arguments?.command)
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
  }

  private struct Usage: Decodable {
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
  }
}
