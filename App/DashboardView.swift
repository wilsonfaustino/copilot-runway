import AppKit
import Charts
import Core
import SwiftUI

struct DashboardView: View {
  static let windowId = "dashboard"
  // Categorical slot 1 of the dataviz reference palette, stepped for each appearance.
  static let barColor = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 0x39 / 255, green: 0x87 / 255, blue: 0xE5 / 255, alpha: 1)
      : NSColor(srgbRed: 0x2A / 255, green: 0x78 / 255, blue: 0xD6 / 255, alpha: 1)
  })
  // Days are UTC days (see Core/README.md), so their labels are formatted in UTC too.
  static let dayLabelStyle = Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated).day()

  let usageStore: UsageStore
  @State private var selectedDayLabel: String?
  @State private var summaryCopied = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        header
        if let usage = usageStore.usage {
          outcomesSection(usage: usage)
          dailyBurnSection(usage: usage)
          HStack(alignment: .top, spacing: 24) {
            shareChart(title: "By source", entries: usageStore.sourceCredits.map { ($0.source.displayName, $0.credits) })
            shareChart(title: "By category", entries: usageStore.categoryCredits.map { ($0.category.displayName, $0.credits) })
          }
          shareChart(
            title: "By model",
            entries: usageStore.modelCredits.compactMap { model in model.credits.map { (model.model, $0) } }
          )
          let unpricedModelCount = usageStore.modelCredits.filter { $0.credits == nil }.count
          if unpricedModelCount > 0 {
            Text("\(unpricedModelCount) model(s) have no price and are not counted.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } else {
          Text(usageStore.errorMessage ?? "Loading usage from GitHub.")
            .foregroundStyle(.secondary)
        }
        if let sessionsWarning = usageStore.sessionsWarning {
          Text(sessionsWarning)
            .foregroundStyle(.orange)
        }
      }
      .padding(24)
    }
    .frame(minWidth: 640, minHeight: 480)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        Text("This billing cycle")
          .font(.title2.bold())
        if let usage = usageStore.usage {
          Text(runwaySentence(usage: usage))
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button(summaryCopied ? "Copied" : "Copy summary") {
        guard let summaryText = usageStore.summaryText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summaryText, forType: .string)
        summaryCopied = true
      }
      .disabled(usageStore.usage == nil)
    }
  }

  private func outcomesSection(usage: CopilotUsage) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Credits per outcome")
        .font(.headline)
      if usageStore.organization == nil {
        Text("Set a GitHub organization in Settings to see credits per outcome.")
          .foregroundStyle(.secondary)
      } else {
        if let outcomes = usageStore.outcomes {
          Text(outcomes.creditsPerOutcome(creditsUsed: usage.creditsUsed).map { "\(credits($0)) credits" } ?? "No PRs yet")
            .font(.largeTitle.bold())
          Text(
            "\(GitHubOutcomes.countText(outcomes.prsOpened)) PRs opened + \(GitHubOutcomes.countText(outcomes.prsReviewed)) PRs reviewed "
              + "this cycle. \(GitHubOutcomes.countText(outcomes.commits)) commits, not counted as outcomes."
          )
          .foregroundStyle(.secondary)
        } else if usageStore.outcomesError == nil {
          Text("Loading outcomes from GitHub.")
            .foregroundStyle(.secondary)
        }
        if let outcomesError = usageStore.outcomesError {
          Text(outcomesError)
            .foregroundStyle(.orange)
        }
      }
    }
  }

  private func dailyBurnSection(usage: CopilotUsage) -> some View {
    let localTotal = usageStore.dailyCredits.reduce(0) { $0 + $1.credits }
    let averageDailyBurn = Runway.averageDailyBurn(usage: usage, now: .now)
    let dayLabels = usageStore.dailyCredits.map { $0.day.formatted(Self.dayLabelStyle) }
    let selectedDay = usageStore.dailyCredits.first { $0.day.formatted(Self.dayLabelStyle) == selectedDayLabel }
    return VStack(alignment: .leading, spacing: 8) {
      Text("Daily burn, from local sessions")
        .font(.headline)
      Text(
        "Local sessions: \(credits(localTotal)) credits. GitHub total: \(credits(usage.creditsUsed)) credits. "
          + "Dashed line: GitHub average, \(credits(averageDailyBurn)) / day. Days are UTC."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
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
          .foregroundStyle(.secondary)
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        if let selectedDay {
          RuleMark(x: .value("Day", selectedDay.day.formatted(Self.dayLabelStyle)))
            .foregroundStyle(.secondary.opacity(0.4))
            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
              Text("\(selectedDay.day.formatted(Self.dayLabelStyle)): \(credits(selectedDay.credits)) credits")
                .font(.caption)
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
      .frame(height: 220)
    }
  }

  private func shareChart(title: String, entries: [(name: String, credits: Double)]) -> some View {
    let total = entries.reduce(0) { $0 + $1.credits }
    return VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      if total > 0 {
        Chart(entries, id: \.name) { entry in
          BarMark(x: .value("Credits", entry.credits), y: .value("Name", entry.name))
            .foregroundStyle(Self.barColor)
            .cornerRadius(4)
            .annotation(position: .trailing) {
              Text("\(credits(entry.credits)) (\(Int((entry.credits / total * 100).rounded()))%)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: 0...(entries.map(\.credits).max() ?? 0) * 1.3)
        .frame(height: CGFloat(entries.count) * 28 + 8)
      } else {
        Text("No local sessions in this cycle.")
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func runwaySentence(usage: CopilotUsage) -> String {
    if usage.isUnlimited { return "\(credits(usage.creditsUsed)) credits used. Unlimited plan." }
    let usedText = "\(credits(usage.creditsUsed)) of \(credits(usage.entitlement)) credits used."
    let resetText = usage.resetDate.formatted(Self.dayLabelStyle)
    guard let runOutDate = Runway.runOutDate(usage: usage, now: .now) else { return "\(usedText) Resets \(resetText)." }
    if runOutDate < usage.resetDate {
      return "\(usedText) At this pace you run out on \(runOutDate.formatted(Self.dayLabelStyle)), before the reset on \(resetText)."
    }
    return "\(usedText) At this pace the credits last until the reset on \(resetText)."
  }

  private func credits(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
  }
}
