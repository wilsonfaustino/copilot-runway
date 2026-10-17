import AppKit
import Charts
import Core
import SwiftUI

struct DashboardView: View {
  static let windowId = "dashboard"
  // Neutral, because the chart is the total over every dimension and blue marks the task card.
  static let barColor = Color.primary.opacity(0.5)
  static let cardTitleFont = Font.system(size: 13, weight: .semibold)
  // Days are UTC days (see Core/README.md), so their labels are formatted in UTC too.
  static let dayLabelStyle = Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated).day()

  let usageStore: UsageStore
  @State private var summaryCopied = false
  @Environment(\.openSettings) private var openSettings

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
      colors: Dictionary(uniqueKeysWithValues: TaskCategory.allCases.map { (.entry($0.displayName), Theme.taskColor($0)) }),
      marksSmallShares: true
    )
  }

  private func modelCard(usage: CopilotUsage) -> some View {
    let breakdown = ShareBreakdown.models(usageStore.modelCredits, githubCredits: usage.creditsUsed)
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
      colors: Theme.modelColors(for: breakdown),
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

  // Items without a color in colors are the folded "Other models" item.
  private func shareCard(
    title: String,
    breakdown: ShareBreakdown,
    colors: [ShareItem.ID: Color],
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
      if !breakdown.isEmpty {
        ShareBreakdownView(
          breakdown: breakdown, colors: colors, marksSmallShares: marksSmallShares, notInLocalSessionsNote: notInLocalSessionsNote
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
private struct DailyBurnChart: View {
  let dailyCredits: [DailyCredits]
  let averageDailyBurn: Double
  let health: RunwayHealth
  @State private var selectedDayLabel: String?

  var body: some View {
    let localTotal = dailyCredits.reduce(0) { $0 + $1.credits }
    let averageColor = Theme.accent(health)
    let dayLabels = dailyCredits.map { $0.day.formatted(DashboardView.dayLabelStyle) }
    let selectedDay = dailyCredits.first { $0.day.formatted(DashboardView.dayLabelStyle) == selectedDayLabel }
    VStack(alignment: .leading, spacing: 12) {
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
            Text("Local sessions, \(Credits.formatted(localTotal)) credits")
          }
          HStack(spacing: Theme.Spacing.small) {
            Path { path in
              path.move(to: CGPoint(x: 0, y: 1))
              path.addLine(to: CGPoint(x: 14, y: 1))
            }
            .stroke(averageColor, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
            .frame(width: 14, height: 2)
            Text("GitHub average, \(Credits.formatted(averageDailyBurn))/day")
          }
        }
        .captionStyle()
        .monospacedDigit()
      }
      Chart {
        ForEach(dailyCredits, id: \.day) { dayCredits in
          BarMark(
            x: .value("Day", dayCredits.day.formatted(DashboardView.dayLabelStyle)),
            y: .value("Credits", dayCredits.credits)
          )
          .foregroundStyle(DashboardView.barColor)
          .cornerRadius(4)
        }
        RuleMark(y: .value("GitHub average", averageDailyBurn))
          .foregroundStyle(averageColor)
          .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
        if let selectedDay {
          RuleMark(x: .value("Day", selectedDay.day.formatted(DashboardView.dayLabelStyle)))
            .foregroundStyle(.secondary.opacity(0.4))
            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
              Text("\(selectedDay.day.formatted(DashboardView.dayLabelStyle)): \(Credits.formatted(selectedDay.credits)) credits")
                .font(.caption)
                .monospacedDigit()
                .padding(4)
                .background(.background, in: RoundedRectangle(cornerRadius: 4))
            }
        }
      }
      .chartXSelection(value: $selectedDayLabel)
      .chartXAxis {
        // Every fifth day, so the labels do not collide.
        AxisMarks(values: dayLabels.enumerated().filter { $0.offset % 5 == 0 }.map(\.element))
      }
      .frame(height: 200)
    }
    .cardStyle(padding: Theme.Spacing.panel)
  }
}
