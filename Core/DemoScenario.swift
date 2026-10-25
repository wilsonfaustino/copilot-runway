#if DEBUG
import Foundation

// Fixed fake data for the Debug-only `-demo <scenario>` launch argument. No value comes from a real
// account or session file. Release builds do not compile this file.
// In every scenario the GitHub credits used are at least the local priced credits, because GitHub also
// counts usage that is not in local sessions.
public struct DemoScenario: Sendable {
  public enum Name: String, CaseIterable, Sendable {
    case typical
    case manyModels = "many-models"
    case heavyPlanning = "heavy-planning"
    case edgeUnpriced = "edge-unpriced"
    case edgeRunout = "edge-runout"
    case edgeUncategorized = "edge-uncategorized"
    case edgeEmpty = "edge-empty"

    // An unknown or empty value gives typical.
    public init(launchValue: String) {
      self = Name(rawValue: launchValue) ?? .typical
    }
  }

  public static let organization = "demo-org"
  static let unpricedModel = "demo-unpriced-model"

  public let name: Name
  public let now: Date
  public let usage: CopilotUsage
  public let turns: [Turn]
  // The last cycle, for the Daily burn ghost line. Kept apart from turns, which hold only this cycle.
  public let previousTurns: [Turn]
  public let outcomes: GitHubOutcomes
  public let copilotReviewCount: Int

  public init(name: Name, now: Date) {
    let shape = Shape.of(name)
    let calendar = Runway.utcCalendar
    let today = calendar.startOfDay(for: now)
    let requestedCycleStart = calendar.date(byAdding: .day, value: -shape.elapsedDays, to: today)!
    let resetDate = calendar.date(byAdding: .month, value: 1, to: requestedCycleStart)!
    let creditsRemaining = shape.entitlement - shape.creditsUsed
    self.name = name
    self.now = now
    usage = CopilotUsage(
      creditsUsed: shape.creditsUsed,
      entitlement: shape.entitlement,
      creditsRemaining: creditsRemaining,
      percentRemaining: creditsRemaining / shape.entitlement * 100,
      isUnlimited: false,
      resetDate: resetDate
    )
    // Month ends can move Runway.cycleStart back a few days. The sessions start on the requested day, so the span
    // and the local credits do not grow past the GitHub total. They still fall inside the app's cycle.
    turns = Self.turns(shape: shape, firstDay: requestedCycleStart, now: now)
    // The last cycle ends before the app's cycle start, so none of it counts in this cycle.
    let cycleStart = Runway.cycleStart(resetDate: resetDate)
    previousTurns = shape.previousTokenScale.map { previousTokenScale in
      Self.turns(
        shape: shape,
        firstDay: Runway.cycleStart(resetDate: cycleStart),
        now: cycleStart.addingTimeInterval(-1),
        scale: previousTokenScale
      )
    } ?? []
    outcomes = shape.outcomes
    copilotReviewCount = shape.copilotReviewCount
  }

  // Bundled prices only, so a prices.json override does not change the demo.
  public var sessionCredits: SessionCredits {
    SessionCredits.aggregate(
      turns: previousTurns + turns, prices: PriceTable.bundled, cycleStart: Runway.cycleStart(resetDate: usage.resetDate), now: now
    )
  }

  // The value after -demo. nil without -demo, and empty when -demo is the last argument.
  public static func launchValue(arguments: [String]) -> String? {
    guard let flagIndex = arguments.firstIndex(of: "-demo") else { return nil }
    let valueIndex = flagIndex + 1
    return arguments.indices.contains(valueIndex) ? arguments[valueIndex] : ""
  }

  struct Shape {
    let entitlement: Double
    let creditsUsed: Double
    let elapsedDays: Int
    let turnsPerDay: Int
    // Each turn takes the next entry, so a repeated model id gets a larger share.
    let models: [String]
    let categories: [TaskCategory]
    let tokenScale: Double
    // Last cycle tokens against this cycle's, nil for no last cycle sessions. The same day pattern repeats in both
    // cycles, but long context pricing is not linear, so typical's 0.81 gives about 35% more credits in this cycle.
    let previousTokenScale: Double?
    let outcomes: GitHubOutcomes
    let copilotReviewCount: Int

    // Repo folders that do not exist on disk, so the project name comes from the folder alone.
    static let projectFolders = [
      "/Users/demo/www/acme/runway-app", "/Users/demo/www/acme/billing-api", "/Users/demo/www/acme/design-system",
      "/Users/demo/www/acme/docs-site", "/Users/demo/www/acme/infra", "/Users/demo/www/acme/mobile-app",
      "/Users/demo/www/acme/data-jobs",
    ]
    // Indexes into projectFolders, one per session in turn. Uneven, so one project leads and two fold into Other.
    static let projectPattern = [0, 1, 0, 2, 0, 0, 3, 1, 0, 4, 0, 2, 5, 0, 1, 6, 0]
    static let typicalModels = ["gpt-6.1-sol", "gpt-6-luna", "gpt-6.1-sol", "gemini-3.8-flash"]
    static let typicalCategories: [TaskCategory] = [
      .implementation, .investigation, .debugging, .implementation, .review, .planning, .investigation,
    ]

    static func of(_ name: Name) -> Shape {
      switch name {
      case .typical:
        Shape(
          entitlement: 1_500, creditsUsed: 760, elapsedDays: 16, turnsPerDay: 6,
          models: typicalModels, categories: typicalCategories, tokenScale: 1,
          previousTokenScale: 0.81,
          outcomes: GitHubOutcomes(prsMerged: 9, prsOpen: 2, prsReviewed: 14, commits: 63), copilotReviewCount: 3
        )
      case .manyModels:
        Shape(
          entitlement: 1_500, creditsUsed: 1_020, elapsedDays: 18, turnsPerDay: 8,
          models: [
            "gpt-6.1-sol", "claude-sonnet-5.5", "gpt-6-luna", "gemini-3.8-flash",
            "claude-opus-5.5", "gpt-5.6-terra", "grok-4.7", "kimi-k3",
          ],
          categories: typicalCategories, tokenScale: 0.55,
          previousTokenScale: 1.1,
          outcomes: GitHubOutcomes(prsMerged: 12, prsOpen: 3, prsReviewed: 20, commits: 88), copilotReviewCount: 5
        )
      case .heavyPlanning:
        Shape(
          entitlement: 1_500, creditsUsed: 700, elapsedDays: 14, turnsPerDay: 6,
          models: typicalModels,
          categories: [.planning, .debugging, .planning, .debugging, .implementation, .planning, .investigation],
          tokenScale: 1,
          previousTokenScale: 0.9,
          outcomes: GitHubOutcomes(prsMerged: 4, prsOpen: 3, prsReviewed: 6, commits: 31), copilotReviewCount: 1
        )
      case .edgeUnpriced:
        Shape(
          entitlement: 1_500, creditsUsed: 720, elapsedDays: 16, turnsPerDay: 6,
          models: typicalModels + [unpricedModel], categories: typicalCategories, tokenScale: 1,
          previousTokenScale: 1,
          outcomes: GitHubOutcomes(prsMerged: 8, prsOpen: 1, prsReviewed: 11, commits: 54), copilotReviewCount: 2
        )
      case .edgeRunout:
        Shape(
          entitlement: 1_500, creditsUsed: 1_540, elapsedDays: 20, turnsPerDay: 9,
          models: typicalModels, categories: typicalCategories, tokenScale: 1,
          previousTokenScale: 0.6,
          outcomes: GitHubOutcomes(prsMerged: 14, prsOpen: 4, prsReviewed: 18, commits: 102), copilotReviewCount: 6
        )
      case .edgeUncategorized:
        Shape(
          entitlement: 1_500, creditsUsed: 90, elapsedDays: 10, turnsPerDay: 5,
          models: typicalModels, categories: [.uncategorized], tokenScale: 1,
          previousTokenScale: nil,
          outcomes: GitHubOutcomes(prsMerged: 1, prsOpen: 1, prsReviewed: 2, commits: 9), copilotReviewCount: 0
        )
      case .edgeEmpty:
        Shape(
          entitlement: 1_500, creditsUsed: 0, elapsedDays: 0, turnsPerDay: 0,
          models: typicalModels, categories: typicalCategories, tokenScale: 1,
          previousTokenScale: nil,
          outcomes: GitHubOutcomes(prsMerged: 0, prsOpen: 0, prsReviewed: 0, commits: 0), copilotReviewCount: 0
        )
      }
    }
  }

  // One turn per slot from the first day through now, 90 minutes apart from 09:00 UTC. scale multiplies the tokens.
  static func turns(shape: Shape, firstDay: Date, now: Date, scale: Double = 1) -> [Turn] {
    let calendar = Runway.utcCalendar
    var turns: [Turn] = []
    var day = firstDay
    var dayIndex = 0
    while day <= now {
      for slot in 0..<shape.turnsPerDay {
        let timestamp = day.addingTimeInterval(Double(9 * 60 + slot * 90) * 60)
        guard timestamp <= now else { break }
        let turnIndex = turns.count
        // Different multipliers, so each model gets a mix of categories.
        let category = shape.categories[(3 * turnIndex + dayIndex) % shape.categories.count]
        let model = shape.models[(turnIndex + dayIndex) % shape.models.count]
        // OpenCode, Pi and omp in turn.
        let sources: [SessionSource] = [.opencode, .pi, .omp]
        let sourceIndex = turnIndex % sources.count
        let source = sources[sourceIndex]
        // One session per day and source.
        let sessionIndex = dayIndex * sources.count + sourceIndex
        let projectFolder = Shape.projectFolders[Shape.projectPattern[sessionIndex % Shape.projectPattern.count]]
        // 0.6, 1.0 or 1.4, so days and models do not all cost the same.
        let variation = 0.6 + 0.4 * Double((turnIndex + 2 * dayIndex) % 3)
        let tokens = tokens(for: category, scale: shape.tokenScale * scale * variation)
        let agent: String?
        if source == .opencode {
          agent = category == .planning ? "plan" : "build"
        } else {
          agent = nil
        }
        turns.append(
          Turn(
            timestamp: timestamp,
            source: source,
            agent: agent,
            toolCalls: toolCalls(for: category, source: source, dayIndex: dayIndex),
            records: [UsageRecord(model: model, timestamp: timestamp.addingTimeInterval(60), tokens: tokens)],
            sessionId: "demo-\(Int(day.timeIntervalSince1970 / 86_400))-\(source.rawValue)",
            directory: projectFolder,
            projectRoot: source == .opencode ? projectFolder : nil
          )
        )
      }
      day = calendar.date(byAdding: .day, value: 1, to: day)!
      dayIndex += 1
    }
    return turns
  }

  // Tool calls that TaskCategorizer maps to the category.
  static func toolCalls(for category: TaskCategory, source: SessionSource, dayIndex: Int) -> [ToolCall] {
    let shellTool = source == .opencode ? "shell" : "bash"
    let sourceFile = "Demo/Sources/Feature\(dayIndex % 4).swift"
    switch category {
    case .investigation:
      return [ToolCall(name: "read", filePath: sourceFile), ToolCall(name: shellTool, command: "rg runway Demo")]
    case .implementation:
      return [ToolCall(name: "read", filePath: sourceFile), ToolCall(name: "edit", filePath: sourceFile)]
    case .debugging:
      return [
        ToolCall(name: "edit", filePath: sourceFile),
        ToolCall(name: shellTool, command: "swift test"),
        ToolCall(name: "edit", filePath: sourceFile),
      ]
    case .review:
      return [ToolCall(name: shellTool, command: "gh pr view 12")]
    // OpenCode Planning comes from the plan agent, Pi and omp Planning from the output tokens.
    case .planning, .uncategorized:
      return []
    }
  }

  static func tokens(for category: TaskCategory, scale: Double) -> TokenUsage {
    func scaled(_ count: Int) -> Int { Int(Double(count) * scale) }
    switch category {
    case .investigation:
      return TokenUsage(input: scaled(12_000), cachedInput: scaled(90_000), cacheWrite: scaled(6_000), output: scaled(1_500))
    case .implementation:
      return TokenUsage(input: scaled(20_000), cachedInput: scaled(160_000), cacheWrite: scaled(10_000), output: scaled(5_000))
    case .debugging:
      return TokenUsage(input: scaled(24_000), cachedInput: scaled(200_000), cacheWrite: scaled(12_000), output: scaled(6_000))
    case .review:
      return TokenUsage(input: scaled(15_000), cachedInput: scaled(60_000), cacheWrite: scaled(5_000), output: scaled(2_000))
    case .planning:
      // At least 1,000 output tokens down to a scale of 0.25, so Pi turns stay Planning.
      return TokenUsage(input: scaled(10_000), cachedInput: scaled(40_000), cacheWrite: scaled(4_000), output: scaled(4_000))
    case .uncategorized:
      // Not scaled: under 1,000 output tokens, so turns without tools stay Uncategorized.
      return TokenUsage(input: 3_000, cachedInput: 10_000, cacheWrite: 0, output: 400)
    }
  }
}
#endif
