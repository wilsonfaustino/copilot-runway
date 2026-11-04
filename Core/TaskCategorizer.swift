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

  // omp is a Pi fork with more tools.
  static let ompToolKinds = piToolKinds.merging(["glob": .read, "ast_grep": .read, "ast_edit": .edit]) { piKind, _ in piKind }

  // Includes the OpenCode 1.x names (bash, edit, write, list), which old sessions still hold.
  static let openCodeToolKinds: [String: ToolKind] = [
    "read": .read, "grep": .read, "glob": .read, "list": .read, "webfetch": .read, "websearch": .read,
    "shell": .shell, "bash": .shell,
    "patch": .edit, "apply_patch": .edit, "edit": .edit, "write": .edit, "multiedit": .edit,
  ]

  // Copilot CLI and app. 0.0.38x sessions use edit, create and grep. 1.0.x GPT sessions use apply_patch and rg.
  // apply_patch has no path argument; the parser takes its paths from tool.execution_complete fileEdits.
  static let copilotToolKinds: [String: ToolKind] = [
    "view": .read, "glob": .read, "grep": .read, "rg": .read, "semantic_code_search": .read,
    "web_fetch": .read, "web_search": .read, "fetch_copilot_cli_documentation": .read,
    "bash": .shell, "write_bash": .shell, "read_bash": .shell,
    "apply_patch": .edit, "edit": .edit, "create": .edit,
  ]

  static let planAgent = "plan"
  static let reviewCommands = ["gh pr diff", "gh pr view"]
  // GitHub MCP pull request reads. Clients prefix the tool name with the server, for example
  // github-mcp-server-pull_request_read (Copilot) or github_get_pull_request (OpenCode).
  static let reviewToolSuffixes = ["pull_request_read", "get_pull_request", "get_pull_request_diff", "get_pull_request_files"]
  // A turn with no read, shell or edit calls is Planning when its Copilot messages wrote at least this many
  // output tokens (reasoning included). In our October 2026 sessions, most such turns had at most 714 output
  // tokens and the next one had 1,082, so the threshold sits in that gap.
  static let planningOutputTokenThreshold = 1_000

  public static func category(of turn: Turn) -> TaskCategory {
    let kinds = turn.toolCalls.map { kind(of: $0, source: turn.source) }
    if isDebugging(turn) { return .debugging }
    if kinds.contains(.edit) { return .implementation }
    if turn.toolCalls.contains(where: { isReviewCommand($0) || isReviewTool($0) }) { return .review }
    if turn.agent == planAgent { return .planning }
    if kinds.contains(.read) || kinds.contains(.shell) { return .investigation }
    // The rules above leave only turns without read, shell or edit calls, outside the plan agent.
    let outputTokens = turn.records.reduce(0) { $0 + $1.tokens.output }
    if outputTokens >= planningOutputTokenThreshold { return .planning }
    return .uncategorized
  }

  static func kind(of toolCall: ToolCall, source: SessionSource) -> ToolKind {
    // omp runs mounted tools by a write to xd://<tool>, which changes no file. A read of xd:// lists tools.
    if toolCall.name != "read", toolCall.filePath?.hasPrefix("xd://") == true { return .other }
    let toolKinds =
      switch source {
      case .pi: piToolKinds
      case .opencode: openCodeToolKinds
      case .omp: ompToolKinds
      case .copilotCli, .copilotApp: copilotToolKinds
      }
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

  static func isReviewTool(_ toolCall: ToolCall) -> Bool {
    reviewToolSuffixes.contains { toolCall.name.hasSuffix($0) }
  }
}
