import AppKit
import Charts
import Core
import SwiftUI

struct DashboardView: View {
  static let windowId = "dashboard"
  static let barColor = Theme.accent(.healthy)
  // Days are UTC days (see Core/README.md), so their labels are formatted in UTC too.
  static let dayLabelStyle = Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated).day()

  let usageStore: UsageStore
  @State private var selectedDayLabel: String?
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
              Text(credits(Runway.averageDailyBurn(usage: usage, now: .now)))
                .bigFigureStyle(size: 34)
              kpiDetail("credits per day")
            }
            outcomesCard(usage: usage)
          }
          .fixedSize(horizontal: false, vertical: true)
          dailyBurnCard(usage: usage, health: health)
          HStack(alignment: .top, spacing: Theme.Spacing.regular) {
            shareCard(title: "By task", entries: usageStore.categoryCredits.map { ($0.category.displayName, $0.credits) })
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
    let lastCycleDay = Runway.utcCalendar.date(byAdding: .day, value: -1, to: usage.resetDate)!
    return "Cycle \(day(cycleStart)) to \(day(lastCycleDay)) · resets \(day(usage.resetDate))"
  }

  // MARK: Insight banner

  private func insightBanner(usage: CopilotUsage, health: RunwayHealth) -> some View {
    let accent = Theme.accent(health)
    let (headline, detail) = bannerText(usage: usage)
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

  private func bannerText(usage: CopilotUsage) -> (headline: String, detail: String) {
    var detailSentences: [String] = []
    let headline: String
    if let errorMessage = usageStore.errorMessage {
      headline = errorMessage
      detailSentences.append("The numbers below are from the last good refresh.")
    } else if usage.isUnlimited {
      headline = "Unlimited plan."
      detailSentences.append("\(credits(usage.creditsUsed)) credits used this cycle.")
    } else if let runOutSentence = RunwayInsight.runOutSentence(usage: usage, now: .now) {
      headline = runOutSentence
      // Rounded down, so the burn stays under the target. A target of 0 is not a useful instruction.
      let targetBurn = RunwayInsight.requiredDailyBurn(usage: usage, now: .now).map { Int($0.rounded(.down)) } ?? 0
      if let runOutDate = Runway.runOutDate(usage: usage, now: .now), runOutDate < usage.resetDate, targetBurn > 0 {
        detailSentences.append("To reach \(day(usage.resetDate)), keep the burn under \(targetBurn.formatted()) credits/day.")
      }
    } else {
      headline = "No credits used yet this cycle."
      detailSentences.append("Resets \(day(usage.resetDate)).")
    }
    if let topShare = RunwayInsight.topCategoryShare(categoryCredits: usageStore.categoryCredits) {
      detailSentences.append("\(topShare.category.displayName) turns use \(topShare.percent)% of local credits.")
    }
    return (headline, detailSentences.joined(separator: " "))
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
        kpiDetail("\(credits(usage.creditsUsed)) used")
      } else {
        Text("\(Runway.wholePercentRemaining(usage: usage))%").bigFigureStyle(size: 34)
        shareBar(fraction: usage.percentRemaining / 100, color: Theme.accent(health))
        kpiDetail("\(credits(usage.creditsUsed)) of \(credits(usage.entitlement)) used")
      }
    }
  }

  private func outcomesCard(usage: CopilotUsage) -> some View {
    kpiCard("Credits per outcome") {
      if usageStore.organization == nil {
        Text("--").bigFigureStyle(size: 34)
        Text("Set a GitHub organization in Settings to see credits per outcome.")
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
          Text(outcomes.creditsPerOutcome(creditsUsed: usage.creditsUsed).map { credits($0) } ?? "No PRs yet")
            .bigFigureStyle(size: 34)
          kpiDetail(
            "\(GitHubOutcomes.countText(outcomes.prsOpened)) PRs opened · \(GitHubOutcomes.countText(outcomes.prsReviewed)) reviewed"
              + " · \(GitHubOutcomes.countText(outcomes.commits)) commits"
          )
          .help("Outcomes are PRs opened plus PRs reviewed this cycle. Commits are not counted as outcomes.")
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

  // MARK: Daily burn

  private func dailyBurnCard(usage: CopilotUsage, health: RunwayHealth) -> some View {
    let localTotal = usageStore.dailyCredits.reduce(0) { $0 + $1.credits }
    let averageDailyBurn = Runway.averageDailyBurn(usage: usage, now: .now)
    // A healthy rule in the bar blue would blend into the bars.
    let averageColor = health == .healthy ? Color.secondary : Theme.accent(health)
    let dayLabels = usageStore.dailyCredits.map { $0.day.formatted(Self.dayLabelStyle) }
    let selectedDay = usageStore.dailyCredits.first { $0.day.formatted(Self.dayLabelStyle) == selectedDayLabel }
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.regular) {
        Text("Daily burn")
          .font(.system(size: 14, weight: .semibold))
        Text("Days are UTC.")
          .captionStyle()
        Spacer()
        HStack(spacing: Theme.Spacing.panel) {
          HStack(spacing: Theme.Spacing.small) {
            RoundedRectangle(cornerRadius: 2)
              .fill(Self.barColor)
              .frame(width: 10, height: 10)
            Text("Local sessions, \(credits(localTotal)) credits")
          }
          HStack(spacing: Theme.Spacing.small) {
            Path { path in
              path.move(to: CGPoint(x: 0, y: 1))
              path.addLine(to: CGPoint(x: 14, y: 1))
            }
            .stroke(averageColor, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
            .frame(width: 14, height: 2)
            Text("GitHub average, \(credits(averageDailyBurn))/day")
          }
        }
        .captionStyle()
        .monospacedDigit()
      }
      Chart {
        ForEach(usageStore.dailyCredits, id: \.day) { dailyCredits in
          BarMark(
            x: .value("Day", dailyCredits.day.formatted(Self.dayLabelStyle)),
            y: .value("Credits", dailyCredits.credits)
          )
          .foregroundStyle(Self.barColor)
          .cornerRadius(4)
        }
        RuleMark(y: .value("GitHub average", averageDailyBurn))
          .foregroundStyle(averageColor)
          .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
        if let selectedDay {
          RuleMark(x: .value("Day", selectedDay.day.formatted(Self.dayLabelStyle)))
            .foregroundStyle(.secondary.opacity(0.4))
            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
              Text("\(selectedDay.day.formatted(Self.dayLabelStyle)): \(credits(selectedDay.credits)) credits")
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

  // MARK: Share cards

  private func modelCard(usage: CopilotUsage) -> some View {
    let pricedModels = usageStore.modelCredits.compactMap { model in model.credits.map { (model.model, $0) } }
    let localTotal = pricedModels.reduce(0) { $0 + $1.1 }
    let unpricedModelCount = usageStore.modelCredits.filter { $0.credits == nil }.count
    var footnotes: [String] = []
    if let percentNotInLocalSessions = RunwayInsight.percentNotInLocalSessions(
      creditsUsed: usage.creditsUsed, localCredits: localTotal
    ) {
      footnotes.append("\(percentNotInLocalSessions)% of GitHub credits are not in local sessions.")
    }
    if unpricedModelCount > 0 {
      footnotes.append("\(unpricedModelCount) model(s) have no price and are not counted.")
    }
    return shareCard(title: "By model", entries: pricedModels, footnotes: footnotes)
  }

  private func agentCard(usage: CopilotUsage) -> some View {
    let sourceCredits = usageStore.sourceCredits
    let creditsPerDay = sourceCredits.map { source in
      "\(source.source.displayName): \(credits(Runway.averageDailyBurn(credits: source.credits, resetDate: usage.resetDate, now: .now))) credits/day."
    }
    return shareCard(
      title: "By agent",
      entries: sourceCredits.map { ($0.source.displayName, $0.credits) },
      footnotes: creditsPerDay.isEmpty ? [] : [creditsPerDay.joined(separator: " ")]
    )
  }

  private func shareCard(title: String, entries: [(name: String, credits: Double)], footnotes: [String] = []) -> some View {
    let total = entries.reduce(0) { $0 + $1.credits }
    return VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      Text(title)
        .font(.system(size: 14, weight: .semibold))
      if total > 0 {
        ForEach(entries, id: \.name) { entry in
          VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack {
              Text(entry.name)
              Spacer()
              Text("\(credits(entry.credits)) · \(Int((entry.credits / total * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .lineLimit(1)
            shareBar(fraction: entry.credits / total, color: Self.barColor)
          }
        }
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

  private func credits(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
  }
}
