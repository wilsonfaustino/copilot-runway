import Foundation

// Pi writes one JSONL file per session. See Core/README.md for the format.
public enum PiSessionParser {
  public static let sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".pi/agent/sessions")
  static let copilotProvider = "github-copilot"

  public static func records(inDirectory directory: URL = sessionsDirectory, since cycleStart: Date) -> [UsageRecord] {
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey]
    ) else { return [] }
    var seenResponseIds = Set<String>()
    var allRecords: [UsageRecord] = []
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
      let modificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      // A file last written before the cycle cannot hold messages from this cycle.
      if let modificationDate, modificationDate < cycleStart { continue }
      guard let fileData = try? Data(contentsOf: fileURL) else { continue }
      allRecords += records(fromJSONL: fileData, since: cycleStart, seenResponseIds: &seenResponseIds)
    }
    return allRecords
  }

  // Forked sessions copy earlier entries, so the same response can appear in more than one file.
  static func records(fromJSONL fileData: Data, since cycleStart: Date, seenResponseIds: inout Set<String>) -> [UsageRecord] {
    let decoder = JSONDecoder()
    var records: [UsageRecord] = []
    for line in fileData.split(separator: UInt8(ascii: "\n")) {
      guard
        let entry = try? decoder.decode(Entry.self, from: Data(line)),
        entry.type == "message",
        let message = entry.message,
        message.role == "assistant",
        message.provider == copilotProvider,
        let model = message.model,
        let usage = message.usage,
        let timestampMilliseconds = message.timestamp
      else { continue }
      let timestamp = Date(timeIntervalSince1970: timestampMilliseconds / 1000)
      guard timestamp >= cycleStart else { continue }
      if let responseId = message.responseId {
        guard seenResponseIds.insert(responseId).inserted else { continue }
      }
      let tokens = TokenUsage(
        input: usage.input ?? 0,
        cachedInput: usage.cacheRead ?? 0,
        cacheWrite: usage.cacheWrite ?? 0,
        // Pi output already counts reasoning tokens: totalTokens = input + output + cacheRead + cacheWrite.
        output: usage.output ?? 0
      )
      records.append(UsageRecord(model: model, timestamp: timestamp, tokens: tokens))
    }
    return records
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
  }

  private struct Usage: Decodable {
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
  }
}
