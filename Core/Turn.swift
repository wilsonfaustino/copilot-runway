import Foundation

public enum SessionSource: String, Sendable {
  case pi
  case opencode
  case omp
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
  // OpenCode session_message.session_id, or the Pi and omp session header id.
  public internal(set) var sessionId: String?
  // The folder the session ran in: OpenCode session_v2.directory, or the Pi and omp session header cwd.
  public internal(set) var directory: String?
  // OpenCode project.worktree, the main repo root even for a linked git worktree. nil for Pi and omp.
  public internal(set) var projectRoot: String?
  // OpenCode session_v2.parent_id, set for subagent sessions. nil for Pi and omp.
  public internal(set) var parentSessionId: String?

  public init(
    timestamp: Date,
    source: SessionSource,
    agent: String? = nil,
    toolCalls: [ToolCall] = [],
    records: [UsageRecord] = [],
    sessionId: String? = nil,
    directory: String? = nil,
    projectRoot: String? = nil,
    parentSessionId: String? = nil
  ) {
    self.timestamp = timestamp
    self.source = source
    self.agent = agent
    self.toolCalls = toolCalls
    self.records = records
    self.sessionId = sessionId
    self.directory = directory
    self.projectRoot = projectRoot
    self.parentSessionId = parentSessionId
  }
}
