import Core
import SwiftUI

struct PopoverView: View {
  let usageStore: UsageStore
  @AppStorage("localOnlyNoticeDismissed") private var localOnlyNoticeDismissed = false
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var openCount = 0

  // Stale numbers stay visible after a fetch error, but faded.
  private static let staleOpacity = 0.45
  private static let entranceOffset: CGFloat = -4
  private static let entranceDuration = 0.15

  var body: some View {
    let now = Date.now
    let health = RunwayHealth(usage: usageStore.usage, hasError: usageStore.usageError != nil, now: now)
    let entranceSlide = reduceMotion ? 0 : Self.entranceOffset
    VStack(alignment: .leading, spacing: Theme.Spacing.section) {
      header
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
        statCards(now: now)
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
    // Each trigger change replays the entrance from progress 0, so every open animates.
    // With Reduce Motion on, the popover only fades.
    .keyframeAnimator(initialValue: 0.0, trigger: openCount) { content, progress in
      content
        .opacity(progress)
        .offset(y: (1 - progress) * entranceSlide)
    } keyframes: { _ in
      LinearKeyframe(1.0, duration: Self.entranceDuration, timingCurve: .easeOut)
    }
    // onAppear may fire only once for window-style content, so a key window change counts each open.
    // onAppear also shows the content if the window name below ever stops matching.
    .onAppear { openCount += 1 }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
      // Settings and the dashboard also become key, so only the menu bar window counts.
      if (notification.object as? NSWindow)?.className.contains("MenuBarExtraWindow") == true { openCount += 1 }
    }
  }

  // applicationIconImage follows the system icon style (Clear renders a low-contrast grey glass). The asset catalog keeps the full-colour icon.
  private static let headerIcon: NSImage = Bundle.main.image(forResource: "AppIcon") ?? NSApplication.shared.applicationIconImage

  private var header: some View {
    HStack {
      HStack(spacing: 8) {
        Image(nsImage: Self.headerIcon)
          .resizable()
          .frame(width: 26, height: 26)
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
      RunwayRing(
        remainingFraction: MenuBarTitle.remainingFraction(usage: usage),
        percentRemaining: usage.map(Runway.wholePercentRemaining),
        accent: accent,
        openCount: openCount
      )
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
        if let usage, let insight = RunwayInsight.popoverSentence(usage: usage, now: now) {
          Text(insight)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

  private func wholeDaysLeft(usage: CopilotUsage?, now: Date) -> Int? {
    usage.flatMap { Runway.wholeDaysLeft(usage: $0, now: now) }
  }

  private func daysFigure(usage: CopilotUsage?, now: Date) -> String {
    if usage?.isUnlimited == true { return "∞" }
    return wholeDaysLeft(usage: usage, now: now).map(String.init) ?? "--"
  }

  private func daysCaption(usage: CopilotUsage?, now: Date) -> String {
    wholeDaysLeft(usage: usage, now: now) == 1 ? "day of runway" : "days of runway"
  }

  private func statCards(now: Date) -> some View {
    let usage = usageStore.usage
    return HStack(spacing: 8) {
      StatCard(
        title: "Used",
        value: usage.map { Credits.formatted($0.creditsUsed) } ?? "--",
        detail: usage.map { $0.isUnlimited ? "unlimited" : "of \(Credits.formatted($0.entitlement))" } ?? " "
      )
      StatCard(
        title: "Daily burn",
        value: usage.map { Credits.formatted(Runway.averageDailyBurn(usage: $0, now: now)) } ?? "--",
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
      value: creditsPerOutcome.map { Credits.formatted($0) } ?? "-",
      detail: usageStore.organization == nil ? "no org set" : "credits each"
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
          Text("local sessions, \(Credits.formatted(pricedTotal))")
            .captionStyle()
            .monospacedDigit()
        }
        ForEach(modelCredits, id: \.model) { model in
          ModelBar(
            name: model.model,
            valueText: model.credits.map { modelCredits in
              "\(Credits.formatted(modelCredits)) · \(Credits.sharePercent(modelCredits, of: pricedTotal))%"
            } ?? "no price",
            share: model.credits.map { pricedTotal > 0 ? $0 / pricedTotal : 0 },
            lowCachePercent: usageStore.cacheHits.first { $0.model == model.model && $0.isLow }?.wholePercent
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
}

private struct RunwayRing: View {
  let remainingFraction: Double
  let percentRemaining: Int?
  let accent: Color
  // Each change replays the sweep from full to the current fraction.
  let openCount: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let diameter: CGFloat = 116
  nonisolated private static let lineWidth: CGFloat = 10
  private static let sweepDuration = 0.7
  private static let refreshDuration = 0.25

  // Same shape as the menu bar gauge: a horseshoe that opens at the bottom.
  nonisolated private static func horseshoe(fraction: Double, color: Color) -> some View {
    Circle()
      .trim(from: 0, to: RunwayGlyph.trackSweepDegrees / 360 * fraction)
      .stroke(color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
      .rotationEffect(.degrees(RunwayGlyph.trackStartDegrees))
  }

  var body: some View {
    let reduceMotion = reduceMotion
    let remainingFraction = remainingFraction
    let accent = accent
    ZStack {
      Self.horseshoe(fraction: 1, color: accent.opacity(RunwayGlyph.trackOpacity))
      // The animator only supplies the progress value. The arc is built from it, so the clear view is not shown.
      Color.clear
        .keyframeAnimator(initialValue: 0.0, trigger: openCount) { _, progress in
          let sweepProgress = reduceMotion ? 1 : progress
          let shownFraction = 1 - (1 - remainingFraction) * sweepProgress
          if shownFraction > 0 {
            Self.horseshoe(fraction: shownFraction, color: accent)
          }
        } keyframes: { _ in
          LinearKeyframe(1.0, duration: Self.sweepDuration, timingCurve: .easeOut)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Self.refreshDuration), value: remainingFraction)
      VStack(spacing: 0) {
        Text(percentRemaining.map { "\($0)%" } ?? "--%")
          .bigFigureStyle()
        Text("left")
          .captionStyle()
      }
    }
    .padding(Self.lineWidth / 2)
    .frame(width: Self.diameter, height: Self.diameter)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      percentRemaining.map { "\($0) percent of credits remaining" } ?? "Credits remaining unknown"
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
  // nil unless the model's cache hit rate is low.
  let lowCachePercent: Int?

  private static let height: CGFloat = 6

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
      HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
        Text(name)
        if let lowCachePercent {
          HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: "exclamationmark.circle")
              .accessibilityHidden(true)
            Text("cache hit \(lowCachePercent)%")
          }
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Theme.accent(.short))
        }
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
