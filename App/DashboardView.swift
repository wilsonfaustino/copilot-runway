import AppKit
import Charts
import Core
import SwiftUI

struct DashboardView: View {
  static let windowId = "dashboard"
  // Neutral, because the chart is the total over every dimension and the task card uses its own hues.
  static let barColor = Color.primary.opacity(0.5)
  static let cardTitleFont = Font.system(size: 13, weight: .semibold)
  // Days are UTC days (see Core/README.md), so their labels are formatted in UTC too.
  static let dayLabelStyle = Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated).day()

  let usageStore: UsageStore
  @State private var summaryCopied = false
  @Environment(\.openSettings) private var openSettings
  @AppStorage(Theme.taskPalettePreferenceKey) private var taskPalettePreference = TaskPalettePreference.unset
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiatesWithoutColor

  private var taskPalette: TaskPalette {
    TaskPalette.resolve(preference: taskPalettePreference, systemDifferentiatesWithoutColor: differentiatesWithoutColor)
  }

  var body: some View {
    let health = RunwayHealth(usage: usageStore.usage, hasError: usageStore.usageError != nil, now: .now)
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.Spacing.panel) {
        if let usage = usageStore.usage {
          insightBanner(usage: usage, health: health)
          HStack(alignment: .top, spacing: Theme.Spacing.regular) {
            runwayCard(usage: usage, health: health)
            remainingCard(usage: usage, health: health)
            kpiCard("Average daily burn") {
              Text(Credits.formatted(Runway.averageDailyBurn(usage: usage, now: .now)))
                .bigFigureStyle(size: 34)
              kpiDetail("credits per day")
            }
            outcomesCard(usage: usage)
          }
          .fixedSize(horizontal: false, vertical: true)
          DailyBurnChart(
            dailyCredits: usageStore.dailyCredits,
            previousDailyCredits: usageStore.previousDailyCredits,
            comparisonSentence: usageStore.cycleComparisonSentence,
            cycleDayCount: Runway.cycleDayCount(resetDate: usage.resetDate),
            averageDailyBurn: Runway.averageDailyBurn(usage: usage, now: .now),
            health: health
          )
          HStack(alignment: .top, spacing: Theme.Spacing.regular) {
            taskCard
            modelCard(usage: usage)
            agentCard(usage: usage)
          }
          .fixedSize(horizontal: false, vertical: true)
        } else {
          Text(usageStore.errorMessage ?? "Loading usage from GitHub.")
            .foregroundStyle(.secondary)
        }
        if let sessionsWarning = usageStore.sessionsWarning {
          Text(sessionsWarning)
            .foregroundStyle(.orange)
        }
      }
      .padding(20)
    }
    .background(.regularMaterial)
    .frame(minWidth: 720, minHeight: 560)
    .navigationSubtitle(cycleSubtitle)
    .onAppear {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate()
      #if DEBUG
      // Demo mode does not save the dashboard frame, so a later real run keeps its own frame.
      if DemoLaunch.scenario != nil {
        NSApp.windows.filter { $0.frameAutosaveName == Self.windowId }.forEach { $0.setFrameAutosaveName("") }
      }
      #endif
    }
    .onDisappear {
      NSApp.setActivationPolicy(.accessory)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          guard let summaryText = usageStore.summaryText() else { return }
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(summaryText, forType: .string)
          summaryCopied = true
        } label: {
          Label(summaryCopied ? "Copied" : "Copy summary", systemImage: "doc.on.doc")
        }
        .labelStyle(.titleAndIcon)
        .disabled(usageStore.usage == nil)
      }
    }
  }

  private var cycleSubtitle: String {
    guard let usage = usageStore.usage else { return "" }
    let cycleStart = Runway.cycleStart(resetDate: usage.resetDate)
    let lastCycleDay = Runway.lastCycleDay(resetDate: usage.resetDate)
    return "Cycle \(day(cycleStart)) to \(day(lastCycleDay)) · resets \(day(usage.resetDate))"
  }

  // MARK: Insight banner

  private func insightBanner(usage: CopilotUsage, health: RunwayHealth) -> some View {
    let accent = Theme.accent(health)
    let (headline, detail) = RunwayInsight.banner(
      usage: usage, errorMessage: usageStore.errorMessage, categoryCredits: usageStore.categoryCredits, now: .now
    )
    return HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.regular) {
      Image(systemName: bannerSymbolName(health: health))
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(accent)
      Text("\(Text(headline).bold()) \(Text(detail).foregroundStyle(.secondary))")
        .font(.system(size: 13.5))
        .lineSpacing(2)
        .textSelection(.enabled)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, Theme.Spacing.panel)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(accent.opacity(0.28)))
  }

  private func bannerSymbolName(health: RunwayHealth) -> String {
    if let usageError = usageStore.usageError { return RunwayGlyph.menuBarSymbolName(error: usageError) }
    switch health {
    case .healthy: return "checkmark.circle"
    case .short: return "exclamationmark.triangle"
    case .critical: return "exclamationmark.octagon"
    case .unavailable: return "questionmark.circle"
    }
  }

  // MARK: KPI cards

  private func kpiCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      Text(title)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
      content()
    }
    .lineLimit(1)
    .minimumScaleFactor(0.6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .cardStyle(padding: Theme.Spacing.panel)
  }

  private func kpiDetail(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 12))
      .monospacedDigit()
  }

  private func runwayCard(usage: CopilotUsage, health: RunwayHealth) -> some View {
    kpiCard("Runway") {
      if usage.isUnlimited {
        Text("∞").bigFigureStyle(size: 34)
        kpiDetail("Unlimited plan")
      } else if let wholeDays = Runway.wholeDaysLeft(usage: usage, now: .now),
        let runOutDate = Runway.runOutDate(usage: usage, now: .now)
      {
        Text(wholeDays == 1 ? "1 day" : "\(wholeDays) days")
          .bigFigureStyle(size: 34)
          .foregroundStyle(Theme.accent(health))
        kpiDetail("Run-out \(day(max(runOutDate, .now)))")
      } else {
        Text("--").bigFigureStyle(size: 34)
        kpiDetail("No burn yet")
      }
    }
  }

  private func remainingCard(usage: CopilotUsage, health: RunwayHealth) -> some View {
    kpiCard("Remaining") {
      if usage.isUnlimited {
        Text("Unlimited").bigFigureStyle(size: 34)
        kpiDetail("\(Credits.formatted(usage.creditsUsed)) used")
      } else {
        Text("\(Runway.wholePercentRemaining(usage: usage))%").bigFigureStyle(size: 34)
        shareBar(fraction: usage.percentRemaining / 100, color: Theme.accent(health))
        kpiDetail("\(Credits.formatted(usage.creditsUsed)) of \(Credits.formatted(usage.entitlement)) used")
      }
    }
  }

  private func outcomesCard(usage: CopilotUsage) -> some View {
    kpiCard("Credits per PR authored") {
      if usageStore.organization == nil {
        Text("--").bigFigureStyle(size: 34)
        Text("Set a GitHub organization in Settings to see credits per PR authored.")
          .font(.system(size: 12))
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
        Button("Open Settings") {
          openSettings()
          NSApplication.shared.activate()
        }
        .buttonStyle(.link)
        .controlSize(.small)
      } else {
        if let outcomes = usageStore.outcomes {
          Text(outcomes.creditsPerPRAuthored(creditsUsed: usage.creditsUsed).map { Credits.formatted($0) } ?? "No PRs yet")
            .bigFigureStyle(size: 34)
          kpiDetail(
            "\(GitHubOutcomes.countText(outcomes.prsMerged)) merged · \(GitHubOutcomes.countText(outcomes.prsOpen)) open"
              + " · \(GitHubOutcomes.countText(outcomes.prsReviewed)) reviewed · \(GitHubOutcomes.countText(outcomes.commits)) commits"
          )
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .help(
            "PRs authored are merged and open PRs you created this cycle. Closed PRs that were not merged, PRs reviewed and commits are not counted."
          )
        } else {
          Text("--").bigFigureStyle(size: 34)
          if usageStore.outcomesError == nil {
            kpiDetail("Loading outcomes from GitHub.")
          }
        }
        if let outcomesError = usageStore.outcomesError {
          Text(outcomesError)
            .font(.system(size: 12))
            .foregroundStyle(.orange)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  // MARK: Share cards

  private var taskCard: some View {
    shareCard(
      title: "By task",
      breakdown: ShareBreakdown.tasks(usageStore.categoryCredits),
      colors: Dictionary(uniqueKeysWithValues: TaskCategory.allCases.map { (.entry($0.displayName), Theme.taskColor($0, palette: taskPalette)) }),
      marksSmallShares: true
    )
  }

  private func modelCard(usage: CopilotUsage) -> some View {
    let breakdown = ShareBreakdown.models(
      usageStore.modelCredits, githubCredits: usage.creditsUsed, namedModelLimit: ShareBreakdown.taskSplitModelLimit
    )
    var footnotes: [String] = []
    if let unpricedModelsNote = ShareBreakdown.unpricedModelsNote(usageStore.modelCredits) {
      footnotes.append(unpricedModelsNote)
    }
    if !usageStore.lowCacheSentences.isEmpty {
      footnotes.append(usageStore.lowCacheSentences.joined(separator: " "))
    }
    if let modelEfficiencyNote = usageStore.modelEfficiencyNote {
      footnotes.append(modelEfficiencyNote)
    }
    return shareCard(
      title: "By model",
      breakdown: breakdown,
      colors: [:],
      taskSplit: ModelTaskSplit(breakdown: breakdown, modelCategoryCredits: usageStore.modelCategoryCredits),
      footnotes: footnotes,
      notInLocalSessionsNote: usageStore.copilotReviewCount.flatMap { reviewCount in
        breakdown.copilotReviewNote(reviewCount: reviewCount, modelCredits: usageStore.modelCredits)
      }
    )
  }

  private func agentCard(usage: CopilotUsage) -> some View {
    let sourceCredits = usageStore.sourceCredits
    let breakdown = ShareBreakdown.local(entries: sourceCredits.map { ($0.source.displayName, $0.credits) })
    let creditsPerDay = sourceCredits.map { source in
      "\(source.source.displayName): \(Credits.formatted(Runway.averageDailyBurn(credits: source.credits, resetDate: usage.resetDate, now: .now))) credits/day."
    }
    return shareCard(
      title: "By agent",
      breakdown: breakdown,
      colors: Dictionary(uniqueKeysWithValues: sourceCredits.map { (.entry($0.source.displayName), Theme.agentColor($0.source)) }),
      footnotes: creditsPerDay.isEmpty ? [] : [creditsPerDay.joined(separator: " ")]
    )
  }

  // Items without a color in colors are the folded "Other models" item. A task split draws one bar per model instead.
  private func shareCard(
    title: String,
    breakdown: ShareBreakdown,
    colors: [ShareItem.ID: Color],
    taskSplit: ModelTaskSplit? = nil,
    footnotes: [String] = [],
    marksSmallShares: Bool = false,
    notInLocalSessionsNote: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
        Text(title)
          .font(Self.cardTitleFont)
        Spacer()
        Text(Credits.formatted(breakdown.shareTotal))
          .bigFigureStyle(size: 26)
        Text(breakdown.unit)
          .captionStyle()
      }
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      if !breakdown.isEmpty, let taskSplit {
        ModelTaskSplitView(
          breakdown: breakdown, taskSplit: taskSplit, taskPalette: taskPalette, notInLocalSessionsNote: notInLocalSessionsNote
        )
      } else if !breakdown.isEmpty {
        ShareBreakdownView(
          breakdown: breakdown, colors: colors, marksSmallShares: marksSmallShares, notInLocalSessionsNote: notInLocalSessionsNote,
          highlightsOnHover: true
        )
      } else {
        Text("No local sessions in this cycle.")
          .captionStyle()
      }
      Spacer(minLength: 0)
      ForEach(footnotes, id: \.self) { footnote in
        Text(footnote)
          .captionStyle()
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .cardStyle(padding: Theme.Spacing.panel)
  }

  private func shareBar(fraction: Double, color: Color) -> some View {
    RoundedRectangle(cornerRadius: Theme.Radius.bar)
      .fill(.quaternary)
      .frame(height: 6)
      .overlay(alignment: .leading) {
        GeometryReader { proxy in
          RoundedRectangle(cornerRadius: Theme.Radius.bar)
            .fill(color)
            .frame(width: proxy.size.width * min(max(fraction, 0), 1))
        }
      }
  }

  private func day(_ date: Date) -> String {
    date.formatted(Self.dayLabelStyle)
  }
}

// Its own view, so a hover change re-renders only the chart and not the whole dashboard.
// The x axis is the day of the cycle, so this cycle's bars and the last cycle's line share the same days.
private struct DailyBurnChart: View {
  // Darker than the bars in light mode and lighter in dark mode. The short dash tells it from the GitHub average.
  static let previousLineColor = Color.primary.opacity(0.85)
  static let previousLineStyle = StrokeStyle(lineWidth: 1.5, dash: [2, 3])
  static let barHalfWidth = 0.35

  let dailyCredits: [DailyCredits]
  let previousDailyCredits: [DailyCredits]
  let comparisonSentence: String?
  let cycleDayCount: Int
  let averageDailyBurn: Double
  let health: RunwayHealth
  @State private var selectedDayPosition: Double?

  static func dayLabel(_ index: Int) -> String {
    "Day \(index + 1)"
  }

  // Bars and lines sit on a numeric day scale, so the axis labels get the width of their tick spacing and not of one day.
  static func dayPosition(_ index: Int) -> Double {
    Double(index + 1)
  }

  private static func labelAnchor(position: Double?, dayCount: Int) -> UnitPoint {
    switch position {
    case 1: .topLeading
    case Double(dayCount): .topTrailing
    default: .top
    }
  }

  // Every fifth day from Day 1 and the last day, with no tick within 2 days of the last day so its label stays readable.
  static func axisDays(dayCount: Int) -> [Double] {
    let fifthDays = stride(from: 1, to: dayCount - 2, by: 5).map(Double.init)
    return fifthDays + [Double(dayCount)]
  }

  var body: some View {
    let localTotal = dailyCredits.reduce(0) { $0 + $1.credits }
    let previousTotal = previousDailyCredits.reduce(0) { $0 + $1.credits }
    let showsPreviousCycle = previousTotal > 0
    let averageColor = Theme.accent(health)
    let dayCount = max(cycleDayCount, dailyCredits.count, showsPreviousCycle ? previousDailyCredits.count : 0)
    let selectedIndex = selectedDayPosition.map { min(max(Int($0.rounded()), 1), dayCount) - 1 }
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.regular) {
          Text("Daily burn")
            .font(DashboardView.cardTitleFont)
          Text("Days are UTC.")
            .captionStyle()
          Spacer()
          HStack(spacing: Theme.Spacing.panel) {
            HStack(spacing: Theme.Spacing.small) {
              RoundedRectangle(cornerRadius: 2)
                .fill(DashboardView.barColor)
                .frame(width: 10, height: 10)
              Text("This cycle, \(Credits.formatted(localTotal)) local credits")
            }
            if showsPreviousCycle {
              HStack(spacing: Theme.Spacing.small) {
                legendLine(color: Self.previousLineColor, style: Self.previousLineStyle)
                Text("Last cycle, \(Credits.formatted(previousTotal)) local credits")
              }
            }
            HStack(spacing: Theme.Spacing.small) {
              legendLine(color: averageColor, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
              Text("GitHub average, \(Credits.formatted(averageDailyBurn))/day")
            }
          }
          .captionStyle()
          .monospacedDigit()
        }
        if let comparisonSentence {
          Text(comparisonSentence)
            .captionStyle()
            .textSelection(.enabled)
        }
      }
      Chart {
        ForEach(Array(dailyCredits.enumerated()), id: \.offset) { index, dayCredits in
          RectangleMark(
            xStart: .value("Day start", Self.dayPosition(index) - Self.barHalfWidth),
            xEnd: .value("Day end", Self.dayPosition(index) + Self.barHalfWidth),
            yStart: .value("Baseline", 0.0),
            yEnd: .value("Credits", dayCredits.credits)
          )
          .foregroundStyle(DashboardView.barColor)
          .cornerRadius(4)
          .accessibilityLabel("This cycle, \(dayCredits.day.formatted(DashboardView.dayLabelStyle))")
          .accessibilityValue("\(Credits.formatted(dayCredits.credits)) local credits")
        }
        if showsPreviousCycle {
          ForEach(Array(previousDailyCredits.enumerated()), id: \.offset) { index, dayCredits in
            LineMark(
              x: .value("Day", Self.dayPosition(index)),
              y: .value("Last cycle credits", dayCredits.credits)
            )
            .foregroundStyle(Self.previousLineColor)
            .lineStyle(Self.previousLineStyle)
            .accessibilityHidden(true)
            // The line is exposed as undated segments, so an invisible mark carries each day's label.
            // A rectangle, like the bars, because Charts folds point marks of one series into those segments too.
            RectangleMark(
              xStart: .value("Day start", Self.dayPosition(index) - 0.05),
              xEnd: .value("Day end", Self.dayPosition(index) + 0.05),
              yStart: .value("Last cycle start", max(dayCredits.credits - 0.5, 0)),
              yEnd: .value("Last cycle credits", dayCredits.credits + 0.5)
            )
            .opacity(0)
            .accessibilityLabel("Last cycle, \(dayCredits.day.formatted(DashboardView.dayLabelStyle))")
            .accessibilityValue("\(Credits.formatted(dayCredits.credits)) local credits")
          }
        }
        RuleMark(y: .value("GitHub average", averageDailyBurn))
          .foregroundStyle(averageColor)
          .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
          .accessibilityLabel("GitHub average")
          .accessibilityValue("\(Credits.formatted(averageDailyBurn)) credits per day")
        if let selectedIndex {
          RuleMark(x: .value("Day", Self.dayPosition(selectedIndex)))
            .foregroundStyle(.secondary.opacity(0.4))
            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))) {
              hoverText(index: selectedIndex, showsPreviousCycle: showsPreviousCycle)
            }
        }
      }
      .chartXScale(domain: 0.5...(Double(dayCount) + 0.5))
      .chartXSelection(value: $selectedDayPosition)
      .chartXAxis {
        AxisMarks(values: Self.axisDays(dayCount: dayCount)) { value in
          let position = value.as(Double.self)
          AxisGridLine()
          AxisTick()
          // The first and last labels start and end at their tick, because a centered label runs past the plot edge.
          AxisValueLabel(anchor: Self.labelAnchor(position: position, dayCount: dayCount)) {
            if let position {
              Text(Self.dayLabel(Int(position) - 1))
            }
          }
        }
      }
      .frame(height: 200)
      .accessibilityLabel("Daily burn")
      .accessibilityValue(accessibilitySummary(localTotal: localTotal, previousTotal: previousTotal))
    }
    .cardStyle(padding: Theme.Spacing.panel)
  }

  private func legendLine(color: Color, style: StrokeStyle) -> some View {
    Path { path in
      path.move(to: CGPoint(x: 0, y: 1))
      path.addLine(to: CGPoint(x: 14, y: 1))
    }
    .stroke(color, style: style)
    .frame(width: 14, height: 2)
  }

  // A day past today has no bar, and a day past the last cycle's length has no last cycle line.
  private func hoverText(index: Int, showsPreviousCycle: Bool) -> some View {
    var lines = [Self.dayLabel(index)]
    if dailyCredits.indices.contains(index) {
      lines.append(hoverLine(dailyCredits[index]))
    }
    if showsPreviousCycle, previousDailyCredits.indices.contains(index) {
      lines.append(hoverLine(previousDailyCredits[index]))
    }
    return Text(lines.joined(separator: "\n"))
      .font(.caption)
      .monospacedDigit()
      .padding(6)
      .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
      .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Color.primary.opacity(0.2)))
  }

  private func hoverLine(_ dayCredits: DailyCredits) -> String {
    "\(dayCredits.day.formatted(DashboardView.dayLabelStyle)): \(Credits.formatted(dayCredits.credits)) credits"
  }

  private func accessibilitySummary(localTotal: Double, previousTotal: Double) -> String {
    var sentences = ["This cycle, \(Credits.formatted(localTotal)) local credits over \(dailyCredits.count) days."]
    if previousTotal > 0 {
      sentences.append("Last cycle, \(Credits.formatted(previousTotal)) local credits.")
    }
    if let comparisonSentence { sentences.append(comparisonSentence) }
    return sentences.joined(separator: " ")
  }
}
