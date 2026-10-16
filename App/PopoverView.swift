import Core
import SwiftUI

struct PopoverView: View {
  let usageStore: UsageStore
  @AppStorage("localOnlyNoticeDismissed") private var localOnlyNoticeDismissed = false
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings

  // Stale numbers stay visible after a fetch error, but faded.
  private static let staleOpacity = 0.45

  var body: some View {
    let now = Date.now
    let health = RunwayHealth(usage: usageStore.usage, hasError: usageStore.usageError != nil, now: now)
    VStack(alignment: .leading, spacing: Theme.Spacing.section) {
      header(health: health)
      if !localOnlyNoticeDismissed {
        localOnlyBanner
      }
      if let errorMessage = usageStore.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Theme.accent(.critical))
          .fixedSize(horizontal: false, vertical: true)
      }
      // Model bars come from local session files, so a fetch error does not make them stale.
      Group {
        runwaySection(health: health, now: now)
        statCards
      }
      .opacity(usageStore.usageError == nil ? 1 : Self.staleOpacity)
      modelBars
      if let sessionsWarning = usageStore.sessionsWarning {
        Label(sessionsWarning, systemImage: "exclamationmark.circle")
          .captionStyle()
          .fixedSize(horizontal: false, vertical: true)
      }
      Divider()
      // The footer row has no room, so the update line sits just above it.
      if let availableVersion = usageStore.availableVersion {
        updateNotice(version: availableVersion)
      }
      footer
    }
    .padding(Theme.Spacing.panel)
    .frame(width: 360)
    .background(.regularMaterial)
  }

  private func header(health: RunwayHealth) -> some View {
    HStack {
      HStack(spacing: 8) {
        RunwayGlyph()
          .stroke(Theme.accent(health), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
          .frame(width: 16, height: 16)
          .frame(width: 26, height: 26)
          .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 7))
          .accessibilityHidden(true)
        Text("Copilot Runway")
          .font(.system(size: 14, weight: .semibold))
      }
      Spacer()
      if let lastRefresh = usageStore.lastRefresh {
        Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
          .captionStyle()
          .monospacedDigit()
      }
    }
  }

  // The notice is always blue, so it does not read as a runway warning.
  private var localOnlyBanner: some View {
    let noticeColor = Theme.accent(.healthy)
    return HStack(alignment: .top, spacing: Theme.Spacing.regular) {
      Image(systemName: "lock")
        .foregroundStyle(noticeColor)
        .accessibilityHidden(true)
      Text("Local only. No telemetry. The only network calls go to api.github.com.")
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        localOnlyNoticeDismissed = true
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.secondary)
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss notice")
    }
    .padding(.vertical, Theme.Spacing.regular)
    .padding(.horizontal, 12)
    .background(noticeColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(noticeColor.opacity(0.22)))
  }

  private func runwaySection(health: RunwayHealth, now: Date) -> some View {
    let usage = usageStore.usage
    let accent = Theme.accent(health)
    return HStack(spacing: 18) {
      RunwayRing(percentRemaining: usage?.percentRemaining, accent: accent)
      VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
          Text(daysFigure(usage: usage, now: now))
            .bigFigureStyle(size: 40)
            .foregroundStyle(accent)
            // Early in a cycle the burn is tiny, so the day count can have 4 or more digits.
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .layoutPriority(1)
          Text(daysCaption(usage: usage, now: now))
            .font(.system(size: 15, weight: .semibold))
        }
        if let usage, let insight = insightText(usage: usage, now: now) {
          Text(insight)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

  // Floored like the menu bar title, so both show the same number.
  private func wholeDaysLeft(usage: CopilotUsage?, now: Date) -> Int? {
    usage.flatMap { Runway.daysLeft(usage: $0, now: now) }.map { Int($0.rounded(.down)) }
  }

  private func daysFigure(usage: CopilotUsage?, now: Date) -> String {
    if usage?.isUnlimited == true { return "∞" }
    return wholeDaysLeft(usage: usage, now: now).map(String.init) ?? "--"
  }

  private func daysCaption(usage: CopilotUsage?, now: Date) -> String {
    wholeDaysLeft(usage: usage, now: now) == 1 ? "day of runway" : "days of runway"
  }

  private func insightText(usage: CopilotUsage, now: Date) -> String? {
    if let runOutSentence = RunwayInsight.runOutSentence(usage: usage, now: now) { return runOutSentence }
    if usage.isUnlimited { return "Unlimited plan. Credits do not run out." }
    if usage.creditsUsed == 0 { return "No credits used yet this cycle." }
    return nil
  }

  private var statCards: some View {
    let usage = usageStore.usage
    return HStack(spacing: 8) {
      StatCard(
        title: "Used",
        value: usage.map { credits($0.creditsUsed) } ?? "--",
        detail: usage.map { $0.isUnlimited ? "unlimited" : "of \(credits($0.entitlement))" } ?? " "
      )
      StatCard(
        title: "Daily burn",
        value: usageStore.averageDailyBurn.map(credits) ?? "--",
        detail: "credits/day"
      )
      perOutcomeCard
    }
  }

  // Without an organization the tile opens Settings, where the organization is set.
  @ViewBuilder
  private var perOutcomeCard: some View {
    let card = StatCard(
      title: "Per outcome",
      value: creditsPerOutcome.map(credits) ?? "-",
      detail: usageStore.organization == nil ? "no org set" : "credits/outcome"
    )
    if usageStore.organization == nil {
      Button {
        openSettings()
        NSApplication.shared.activate()
      } label: {
        card
      }
      .buttonStyle(.plain)
      .help("Set a GitHub organization in Settings")
      .accessibilityHint("Opens Settings")
    } else {
      card
    }
  }

  private var creditsPerOutcome: Double? {
    guard usageStore.organization != nil, let usage = usageStore.usage else { return nil }
    return usageStore.outcomes?.creditsPerOutcome(creditsUsed: usage.creditsUsed)
  }

  @ViewBuilder
  private var modelBars: some View {
    let modelCredits = usageStore.modelCredits
    if !modelCredits.isEmpty {
      // Models without a price are listed but left out of the total.
      let pricedTotal = modelCredits.compactMap(\.credits).reduce(0, +)
      VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
        HStack(alignment: .firstTextBaseline) {
          Text("By model")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
          Spacer()
          Text("local sessions, \(credits(pricedTotal))")
            .captionStyle()
            .monospacedDigit()
        }
        ForEach(modelCredits, id: \.model) { model in
          ModelBar(
            name: model.model,
            valueText: model.credits.map(credits) ?? "no price",
            share: model.credits.map { pricedTotal > 0 ? $0 / pricedTotal : 0 }
          )
        }
      }
    }
  }

  private func updateNotice(version: String) -> some View {
    HStack(spacing: Theme.Spacing.small) {
      Text("Version \(version) is available.")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
      Spacer()
      Button("Copy brew command") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ReleaseCheck.upgradeCommand, forType: .string)
      }
      .controlSize(.small)
      .help(ReleaseCheck.upgradeCommand)
    }
  }

  private var footer: some View {
    HStack(spacing: Theme.Spacing.small) {
      Button {
        openWindow(id: DashboardView.windowId)
        // The app has no Dock icon, so it must come forward or the window opens behind other apps.
        NSApplication.shared.activate()
      } label: {
        Label("Open dashboard", systemImage: "chart.bar.xaxis")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(FooterButtonStyle(fillOpacity: 0.10))
      // SettingsLink has no action to bring the app forward, so this button opens Settings itself.
      Button {
        openSettings()
        NSApplication.shared.activate()
      } label: {
        Image(systemName: "gearshape")
          .frame(width: 16)
      }
      .buttonStyle(FooterButtonStyle(fillOpacity: 0.06))
      .accessibilityLabel("Settings")
      Button {
        NSApplication.shared.terminate(nil)
      } label: {
        Image(systemName: "power")
          .frame(width: 16)
      }
      .buttonStyle(FooterButtonStyle(fillOpacity: 0.06))
      .accessibilityLabel("Quit Copilot Runway")
    }
  }

  private func credits(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
  }
}

private struct RunwayRing: View {
  let percentRemaining: Double?
  let accent: Color

  private static let diameter: CGFloat = 116
  private static let lineWidth: CGFloat = 10

  var body: some View {
    let fraction = min(max((percentRemaining ?? 0) / 100, 0), 1)
    ZStack {
      Circle()
        .stroke(Color.primary.opacity(0.08), lineWidth: Self.lineWidth)
      Circle()
        .trim(from: 0, to: fraction)
        .stroke(accent, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
      VStack(spacing: 0) {
        Text(percentRemaining.map { "\(Int($0.rounded()))%" } ?? "--%")
          .bigFigureStyle()
        Text("left")
          .captionStyle()
      }
    }
    .padding(Self.lineWidth / 2)
    .frame(width: Self.diameter, height: Self.diameter)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      percentRemaining.map { "\(Int($0.rounded())) percent of credits remaining" } ?? "Credits remaining unknown"
    )
  }
}

private struct StatCard: View {
  let title: String
  let value: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
      Text(title)
        .captionStyle()
      Text(value)
        .font(.system(size: 15, weight: .semibold))
        .monospacedDigit()
      Text(detail)
        .captionStyle()
        .monospacedDigit()
    }
    .lineLimit(1)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardStyle()
    .accessibilityElement(children: .combine)
  }
}

private struct ModelBar: View {
  let name: String
  let valueText: String
  // nil when the model has no price, so it has no bar.
  let share: Double?

  private static let height: CGFloat = 6

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
      HStack {
        Text(name)
        Spacer()
        Text(valueText)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      .font(.system(size: 12))
      RoundedRectangle(cornerRadius: Theme.Radius.bar)
        .fill(Color.primary.opacity(0.07))
        .frame(height: Self.height)
        .overlay(alignment: .leading) {
          GeometryReader { geometry in
            RoundedRectangle(cornerRadius: Theme.Radius.bar)
              .fill(Theme.accent(.healthy))
              .frame(width: geometry.size.width * min(max(share ?? 0, 0), 1))
          }
        }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct FooterButtonStyle: ButtonStyle {
  let fillOpacity: Double

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .padding(.horizontal, Theme.Spacing.regular)
      .frame(height: 32)
      .background(
        Color.primary.opacity(configuration.isPressed ? fillOpacity + 0.08 : fillOpacity),
        in: RoundedRectangle(cornerRadius: Theme.Radius.control)
      )
      .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
  }
}
