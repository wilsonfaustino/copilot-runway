import Foundation

public enum SessionSource: String, Sendable {
  case pi
  case opencode
}

public struct ToolCall: Equatable, Sendable {
  // The name the client uses. TaskCategorizer maps it per source.
  public let name: String
  // Set for read, edit and write tools.
  public let filePath: String?
  // Set for shell tools.
  public let command: String?

  public init(name: String, filePath: String? = nil, command: String? = nil) {
    self.name = name
    self.filePath = filePath
    self.command = command
  }
}

// One user message plus all assistant messages and tool calls until the next user message.
public struct Turn: Equatable, Sendable {
  // Time of the user message. A turn without a user message in range starts at its first assistant message.
  public let timestamp: Date
  public let source: SessionSource
  // OpenCode agent of the first assistant message, for example "plan". Pi has no agents.
  public internal(set) var agent: String?
  public internal(set) var toolCalls: [ToolCall]
  // Assistant messages billed through GitHub Copilot in the cycle, the same records Credits.byModel gets.
  public internal(set) var records: [UsageRecord]

  public init(timestamp: Date, source: SessionSource, agent: String? = nil, toolCalls: [ToolCall] = [], records: [UsageRecord] = []) {
    self.timestamp = timestamp
    self.source = source
    self.agent = agent
    self.toolCalls = toolCalls
    self.records = records
  }
}
