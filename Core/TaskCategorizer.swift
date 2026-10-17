import Foundation

// Declared in precedence order: when a turn matches several rules, the first one wins.
// One exception: the plan agent rule for Planning comes before Investigation. See TaskCategorizer.category(of:).
public enum TaskCategory: String, CaseIterable, Sendable {
  case debugging
  case implementation
  case review
  case investigation
  case planning
  case uncategorized
}

// Deterministic rules from the tool calls in a turn. See Core/README.md for the tool name mapping.
public enum TaskCategorizer {
  enum ToolKind {
    // Reads files, searches files, or fetches from the web.
    case read
    case shell
    // Changes a file. Every edited file counts as a source file.
    case edit
    // Does not change the category: skills, questions, todos, subagents, MCP tools and others.
    case other
  }

  static let piToolKinds: [String: ToolKind] = [
    "read": .read, "grep": .read, "find": .read, "ls": .read,
    "bash": .shell,
    "edit": .edit, "write": .edit,
  ]

  // Includes the OpenCode 1.x names (bash, edit, write, list), which old sessions still hold.
  static let openCodeToolKinds: [String: ToolKind] = [
    "read": .read, "grep": .read, "glob": .read, "list": .read, "webfetch": .read, "websearch": .read,
    "shell": .shell, "bash": .shell,
    "patch": .edit, "apply_patch": .edit, "edit": .edit, "write": .edit, "multiedit": .edit,
  ]

  static let planAgent = "plan"
  static let reviewCommands = ["gh pr diff", "gh pr view"]
  // A turn with no read, shell or edit calls is Planning when its Copilot messages wrote at least this many
  // output tokens (reasoning included). In our October 2026 sessions, most such turns had at most 714 output
  // tokens and the next one had 1,082, so the threshold sits in that gap.
  static let planningOutputTokenThreshold = 1_000

  public static func category(of turn: Turn) -> TaskCategory {
    let kinds = turn.toolCalls.map { kind(of: $0, source: turn.source) }
    if isDebugging(turn) { return .debugging }
    if kinds.contains(.edit) { return .implementation }
    if turn.toolCalls.contains(where: isReviewCommand) { return .review }
    if turn.agent == planAgent { return .planning }
    if kinds.contains(.read) || kinds.contains(.shell) { return .investigation }
    // The rules above leave only turns without read, shell or edit calls, outside the plan agent.
    let outputTokens = turn.records.reduce(0) { $0 + $1.tokens.output }
    if outputTokens >= planningOutputTokenThreshold { return .planning }
    return .uncategorized
  }

  static func kind(of toolCall: ToolCall, source: SessionSource) -> ToolKind {
    let toolKinds = source == .pi ? piToolKinds : openCodeToolKinds
    return toolKinds[toolCall.name] ?? .other
  }

  // Edit a file, run a shell command, then edit the same file again.
  static func isDebugging(_ turn: Turn) -> Bool {
    var editedFiles = Set<String>()
    var filesEditedBeforeRun = Set<String>()
    for toolCall in turn.toolCalls {
      switch kind(of: toolCall, source: turn.source) {
      case .shell:
        filesEditedBeforeRun.formUnion(editedFiles)
      case .edit:
        guard let filePath = toolCall.filePath else { continue }
        if filesEditedBeforeRun.contains(filePath) { return true }
        editedFiles.insert(filePath)
      case .read, .other:
        continue
      }
    }
    return false
  }

  // Substring match, so wrapped commands such as `rtk gh pr view 12` also count.
  static func isReviewCommand(_ toolCall: ToolCall) -> Bool {
    guard let command = toolCall.command else { return false }
    return reviewCommands.contains { command.contains($0) }
  }
}
