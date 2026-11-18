import Core
import SwiftUI

struct PopoverView: View {
  let usageStore: UsageStore
  let closePopover: () -> Void
  // The share card renders this view without controls and notices.
  var forShare = false
  var share: (NSView) -> Void = { _ in
    // No-op default: only the live popover wires sharing.
  }
  @AppStorage("localOnlyNoticeDismissed") private var localOnlyNoticeDismissed = false
  @AppStorage("whatsNewLastSeenVersion") private var whatsNewLastSeenVersion: String?
  @Environment(\.openWindow) private var openWindow
  @State private var openCount = 0
  @State private var shareAnchor = ShareAnchor()

  // Stale numbers stay visible after a fetch error, but faded.
  private static let staleOpacity = 0.45

  var body: some View {
    let now = Date.now
    let health = RunwayHealth(usage: usageStore.gaugeUsage, hasError: usageStore.hasUsageError, now: now, days: usageStore.runwayDays)
    VStack(alignment: .leading, spacing: Theme.Spacing.section) {
      header
      if !forShare && !localOnlyNoticeDismissed {
        localOnlyBanner
      }
      if !forShare, let whatsNew = whatsNewDecision.banner {
        whatsNewBanner(whatsNew)
      }
      if !forShare {
        copilotStatusRow
      }
      if !forShare, case .noPortkeyData = usageStore.copilotState,
        usageStore.usageError.flatMap(PortkeyOnly.absence(for:)) != nil
      {
        noPortkeyDataCard
      }
      // Model bars come from local session files, so a fetch error does not make them stale.
      Group {
        runwaySection(health: health, now: now)
        statCards(now: now)
      }
      .opacity(usageStore.hasUsageError ? Self.staleOpacity : 1)
      if !usageStore.isPortkeyOnly {
        modelBars
      }
      if !forShare, let sessionsWarning = usageStore.sessionsWarning {
        Label(sessionsWarning, systemImage: "exclamationmark.circle")
          .captionStyle()
          .fixedSize(horizontal: false, vertical: true)
      }
      portkeyCard(now: now)
      if forShare {
        Text("Copilot Runway · \(now.formatted(.dateTime.month(.abbreviated).day()))")
          .captionStyle()
      } else {
        Divider()
        // The footer row has no room, so the update line sits just above it.
        if let availableVersion = usageStore.availableVersion {
          updateNotice(version: availableVersion)
        }
        footer
      }
    }
    .padding(Theme.Spacing.panel)
    .frame(width: 360)
    // NSPopover keeps this view between shows, so onAppear fires only on the first show.
    // That first show may also post willShow, and a second bump only restarts the ring sweep.
    .onAppear {
      openCount += 1
      storeWhatsNewBaselineIfNoBanner()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) { _ in
      openCount += 1
      // UpdateControls' .task does not run again on a later show, so a brew check that did not finish retries here.
      Task { await usageStore.appUpdater.prepareIfNeeded() }
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
      if usageStore.isPortkeyOnly {
        Text("Portkey only")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .overlay(Capsule().strokeBorder(Color.primary.opacity(0.16)))
      }
      Spacer()
      if let lastRefresh = usageStore.lastRefresh {
        Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
          .captionStyle()
          .monospacedDigit()
      }
    }
  }

  @ViewBuilder
  private var copilotStatusRow: some View {
    switch usageStore.copilotState {
    case .portkeyOnly(let absence):
      Label(PortkeyOnly.causeLine(absence, hasBudget: usageStore.portkeyBudgetUSD != nil), systemImage: "info.circle")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    case .copilot, .noPortkeyData:
      if let errorMessage = usageStore.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Theme.accent(.critical))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var noPortkeyDataCard: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      Text("Using Portkey without Copilot?")
        .font(.system(size: 12, weight: .semibold))
      Text("Copilot Runway also shows Portkey spend from OpenCode, Pi and omp sessions. It found no Portkey requests this month. Set a monthly budget in Settings to see runway.")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button("Open Settings") { openSourcesSettings() }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardStyle()
  }

  private func openSourcesSettings() {
    usageStore.settingsTab = .sources
    SettingsWindowController.show(usageStore: usageStore)
    closePopover()
  }

  private var whatsNewDecision: WhatsNew.Decision {
    WhatsNew.decide(
      currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
      lastSeenVersion: whatsNewLastSeenVersion,
      isExistingUser: localOnlyNoticeDismissed
    )
  }

  // A fresh install or a release without notes moves the baseline at once, so a later release still shows its notes.
  private func storeWhatsNewBaselineIfNoBanner() {
    guard !forShare, let versionToStore = whatsNewDecision.versionToStore else { return }
    #if DEBUG
    // Demo mode must not write the real preference.
    if DemoLaunch.isActive { return }
    #endif
    whatsNewLastSeenVersion = versionToStore
  }

  // Same look as the Local only notice.
  private func whatsNewBanner(_ whatsNew: WhatsNew) -> some View {
    let noticeColor = Theme.accent(.healthy)
    return HStack(alignment: .top, spacing: Theme.Spacing.regular) {
      Image(systemName: "sparkles")
        .foregroundStyle(noticeColor)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text("What's New in \(whatsNew.version)")
          .font(.system(size: 12, weight: .semibold))
        ForEach(whatsNew.lines, id: \.self) { line in
          Text(line)
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
        }
        Link("Release notes", destination: whatsNew.releaseNotesURL)
          .font(.system(size: 12))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        whatsNewLastSeenVersion = whatsNew.version
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.secondary)
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss What's New")
      #if DEBUG
      // Demo mode must not write the real preference.
      .disabled(DemoLaunch.isActive)
      #endif
    }
    .padding(.vertical, Theme.Spacing.regular)
    .padding(.horizontal, 12)
    .background(noticeColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(noticeColor.opacity(0.22)))
    .accessibilityElement(children: .contain)
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
      #if DEBUG
      // Demo mode must not write the real preference.
      .disabled(DemoLaunch.isActive)
      #endif
    }
    .padding(.vertical, Theme.Spacing.regular)
    .padding(.horizontal, 12)
    .background(noticeColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(noticeColor.opacity(0.22)))
  }

  private func runwaySection(health: RunwayHealth, now: Date) -> some View {
    let usage = usageStore.gaugeUsage
    let combined = usageStore.combinedBudget
    let gaugeMode = usageStore.gaugeMode
    let accent = Theme.accent(health)
    let budgetUnit: BudgetUnit = combined == nil && !usageStore.isPortkeyOnly ? .credits : .usd
    let hasNoBudget = usageStore.isPortkeyOnly && usageStore.portkeyBudgetUSD == nil
    return VStack(alignment: .leading, spacing: Theme.Spacing.section) {
      HStack(spacing: 18) {
        RunwayRing(
          parts: usageStore.gaugeParts,
          gaugePercent: usage.map { Runway.wholeGaugePercent(usage: $0, mode: gaugeMode) },
          gaugeMode: gaugeMode,
          accent: accent,
          combined: combined,
          openCount: openCount,
          isStatic: forShare,
          hasNoBudget: hasNoBudget,
          isPortkeyOnly: usageStore.isPortkeyOnly
        )
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
          if hasNoBudget {
            noBudgetFigure
            if !forShare {
              Button("Set a monthly budget to see runway") { openSourcesSettings() }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .multilineTextAlignment(.leading)
            }
          } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
              // "Lasts the cycle" leaves no room for the caption beside it, so the caption goes underneath.
              let lastsTheCycle = lastsTheCycle(usage: usage, now: now)
              let figureLayout = lastsTheCycle
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.small))
              figureLayout {
                Text(daysFigure(usage: usage, now: now))
                  .bigFigureStyle(size: lastsTheCycle ? 24 : 40)
                  .foregroundStyle(accent)
                  // Early in a cycle the burn is tiny, so the day count can have 4 or more digits.
                  .lineLimit(1)
                  .minimumScaleFactor(0.5)
                  .layoutPriority(1)
                Text(daysCaption(usage: usage, now: now))
                  .font(.system(size: 15, weight: .semibold))
                  .lineLimit(1)
              }
              if let usage, let insight = RunwayInsight.popoverSentence(usage: usage, now: now, days: usageStore.runwayDays, unit: budgetUnit) {
                Text(insight)
                  .font(.system(size: 12.5))
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
                  .fixedSize(horizontal: false, vertical: true)
              }
              if !forShare, let usage, case .workdays(_, let daysOff) = usageStore.runwayDays {
                let daysOffCount = DaysOffGrid.inCycle(daysOff, resetDate: usage.resetDate).count
                if daysOffCount > 0 {
                  Label("Excludes \(daysOffCount) \(daysOffCount == 1 ? "day" : "days") off", systemImage: "calendar")
                    .captionStyle()
                }
              }
            }
            .accessibilityElement(children: .combine)
          }
        }
      }
      if let combined, !usageStore.isPortkeyOnly {
        combinedBox(combined: combined, gaugeMode: gaugeMode, accent: accent)
      }
    }
  }

  private var noBudgetFigure: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
      Text(PortkeySpend.formatted(usageStore.portkeySpend.totalUSD))
        .bigFigureStyle(size: 40)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      Text("spent this month")
        .font(.system(size: 15, weight: .semibold))
        .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
  }

  private func combinedBox(combined: CombinedBudget, gaugeMode: GaugeMode, accent: Color) -> some View {
    let budgetText = PortkeySpend.formatted(combined.usage.entitlement)
    let header = gaugeMode == .spent
      ? "\(PortkeySpend.formatted(combined.usage.creditsUsed)) of \(budgetText) spent"
      : "\(PortkeySpend.formatted(max(combined.usage.creditsRemaining, 0))) of \(budgetText) left"
    return VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      Text("Copilot + Portkey · \(header)")
        .captionStyle()
      GaugeLegend(amountsUSD: combined.amountsUSD(mode: gaugeMode), color: accent)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardStyle()
    .accessibilityElement(children: .combine)
  }

  private func wholeDaysLeft(usage: QuotaUsage?, now: Date) -> Int? {
    usage.flatMap { Runway.wholeDaysLeft(usage: $0, now: now, days: usageStore.runwayDays) }
  }

  private func lastsTheCycle(usage: QuotaUsage?, now: Date) -> Bool {
    usage.map { Runway.lastsTheCycle(usage: $0, now: now, days: usageStore.runwayDays) } ?? false
  }

  private func daysFigure(usage: QuotaUsage?, now: Date) -> String {
    if usage?.isUnlimited == true { return "∞" }
    if lastsTheCycle(usage: usage, now: now) { return "Lasts the cycle" }
    return wholeDaysLeft(usage: usage, now: now).map(String.init) ?? "--"
  }

  private func daysCaption(usage: QuotaUsage?, now: Date) -> String {
    if let usage, lastsTheCycle(usage: usage, now: now) { return RunwayInsight.resetCaption(usage: usage) }
    let wholeDays = wholeDaysLeft(usage: usage, now: now)
    return "\(usageStore.runwayDays.dayWord(count: wholeDays ?? 0)) of runway"
  }

  @ViewBuilder
  private func statCards(now: Date) -> some View {
    if usageStore.isPortkeyOnly {
      portkeyOnlyStatCards(now: now)
    } else {
      copilotStatCards(now: now)
    }
  }

  private func portkeyOnlyStatCards(now: Date) -> some View {
    let spend = usageStore.portkeySpend
    let dailyBurn = usageStore.cycleResetDate.map {
      Runway.averageDailyBurn(credits: spend.totalUSD, resetDate: $0, now: now, days: usageStore.runwayDays)
    }
    return HStack(spacing: 8) {
      if let budgetUSD = usageStore.portkeyBudgetUSD {
        StatCard(
          title: "Spent",
          value: PortkeySpend.formatted(spend.totalUSD),
          detail: "of \(PortkeySpend.formatted(budgetUSD))"
        )
      }
      StatCard(
        title: "Daily burn",
        value: dailyBurn.map { PortkeySpend.formatted($0) } ?? "--",
        detail: "USD/\(usageStore.runwayDays.dayWord())"
      )
      StatCard(title: "Requests", value: String(spend.requestCount), detail: "this month")
    }
  }

  private func copilotStatCards(now: Date) -> some View {
    let usage = usageStore.usage
    return HStack(spacing: 8) {
      StatCard(
        title: "Used",
        value: usage.map { Credits.formatted($0.creditsUsed) } ?? "--",
        detail: usage.map { $0.isUnlimited ? "unlimited" : "of \(Credits.formatted($0.entitlement))" } ?? " "
      )
      StatCard(
        title: "Daily burn",
        value: usage.map { Credits.formatted(Runway.averageDailyBurn(usage: $0, now: now, days: usageStore.runwayDays)) } ?? "--",
        detail: "credits/\(usageStore.runwayDays.dayWord())"
      )
      perPRCard
    }
  }

  // Without an organization the tile opens Settings, where the organization is set.
  @ViewBuilder
  private var perPRCard: some View {
    let card = StatCard(
      title: "Per PR",
      value: creditsPerPRAuthored.map { Credits.formatted($0) } ?? "-",
      detail: usageStore.organization == nil ? "no org set" : "credits each"
    )
    if usageStore.organization == nil && !forShare {
      Button {
        openSourcesSettings()
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

  private var creditsPerPRAuthored: Double? {
    guard usageStore.organization != nil, let usage = usageStore.usage else { return nil }
    return usageStore.outcomes?.creditsPerPRAuthored(creditsUsed: usage.creditsUsed)
  }

  @ViewBuilder
  private var modelBars: some View {
    let modelCredits = usageStore.modelCredits
    if !modelCredits.isEmpty {
      let breakdown = ShareBreakdown.models(modelCredits, githubCredits: usageStore.usage?.creditsUsed ?? 0)
      VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
        HStack(alignment: .firstTextBaseline) {
          Text("By model")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
          Spacer()
          Text("\(breakdown.unit), \(Credits.formatted(breakdown.shareTotal))")
            .captionStyle()
            .monospacedDigit()
        }
        ShareBreakdownView(
          breakdown: breakdown,
          colors: Theme.modelColors(for: breakdown),
          lowCachePercents: ShareBreakdown.lowCachePercents(usageStore.cacheHits),
          unpricedModels: ShareBreakdown.unpricedModels(modelCredits),
          notInLocalSessionsNote: usageStore.copilotReviewCount.flatMap { reviewCount in
            breakdown.copilotReviewNote(reviewCount: reviewCount, modelCredits: modelCredits)
          }
        )
      }
    }
  }

  @ViewBuilder
  private func portkeyCard(now: Date) -> some View {
    let spend = usageStore.portkeySpend
    if PortkeyBudget.showsBlock(requestCount: spend.requestCount, budgetUSD: usageStore.portkeyBudgetUSD) {
      PortkeyCard(
        spend: spend,
        budgetStatus: usageStore.usage.flatMap {
          PortkeyBudget.status(spentUSD: spend.totalUSD, budgetUSD: usageStore.portkeyBudgetUSD, resetDate: $0.resetDate, now: now, days: usageStore.runwayDays)
        },
        showsCostSourceNote: !forShare,
        showsSetupPrompt: !forShare
      )
    }
  }

  private func updateNotice(version: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      HStack(spacing: Theme.Spacing.small) {
        Text("Version \(version) is available.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
        Spacer()
        UpdateControls(appUpdater: usageStore.appUpdater)
      }
      UpdateStatusRow(appUpdater: usageStore.appUpdater)
    }
  }

  private var footer: some View {
    HStack(spacing: Theme.Spacing.small) {
      Button {
        if let anchorView = shareAnchor.view { share(anchorView) }
      } label: {
        Image(systemName: "square.and.arrow.up")
          .frame(width: 16)
      }
      .buttonStyle(FooterButtonStyle(fillOpacity: 0.06))
      .background(ShareAnchorView(anchor: shareAnchor))
      .accessibilityLabel("Share")
      .disabled(!(usageStore.isPortkeyOnly || (usageStore.usage != nil && usageStore.usageError == nil)))
      Button {
        openWindow(id: DashboardView.windowId)
        // The app has no Dock icon, so it must come forward or the window opens behind other apps.
        NSApplication.shared.activate()
        closePopover()
      } label: {
        Label("Open dashboard", systemImage: "chart.bar.xaxis")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(FooterButtonStyle(fillOpacity: 0.10))
      Button {
        SettingsWindowController.show(usageStore: usageStore)
        closePopover()
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
  let parts: GaugeParts
  let gaugePercent: Int?
  let gaugeMode: GaugeMode
  let accent: Color
  let combined: CombinedBudget?
  // Each change replays the sweep from the mode's start fraction to the current fraction.
  let openCount: Int
  // ImageRenderer draws one frame, where the animator is still at its start fraction.
  let isStatic: Bool
  // Portkey only with no budget: the ring is an empty track with no percent.
  let hasNoBudget: Bool
  let isPortkeyOnly: Bool

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

  // Same order as the menu bar glyph: the Portkey tone up to the total, then the Copilot part on top.
  // The ZStack keeps the two arcs on one circle: inside keyframeAnimator, loose sibling views stack vertically.
  nonisolated private static func arcs(parts: GaugeParts, color: Color) -> some View {
    ZStack {
      if parts.portkey > 0 {
        horseshoe(fraction: parts.total, color: color.opacity(RunwayGlyph.portkeyOpacity))
      }
      if parts.copilot > 0 {
        horseshoe(fraction: parts.copilot, color: color)
      }
    }
  }

  // Both parts scale by the shown total over the target total, so their ratio holds during the sweep.
  nonisolated private static func shownParts(target: GaugeParts, shownTotal: Double) -> GaugeParts {
    guard target.total > 0 else { return GaugeParts(copilot: shownTotal, portkey: 0) }
    let scale = shownTotal / target.total
    return GaugeParts(copilot: target.copilot * scale, portkey: target.portkey * scale)
  }

  private var accessibilityText: String {
    if hasNoBudget { return "No Portkey budget set" }
    let percentText = gaugePercent.map(String.init)
    if let combined, let percentText {
      let amounts = combined.amountsUSD(mode: gaugeMode)
      let copilotText = PortkeySpend.formatted(amounts.copilot)
      let portkeyText = PortkeySpend.formatted(amounts.portkey)
      let state = gaugeMode == .spent ? "spent" : "left"
      return "\(percentText) percent of combined budget \(state). Copilot \(copilotText), Portkey \(portkeyText)."
    }
    if isPortkeyOnly {
      let state = gaugeMode == .spent ? "spent" : "left"
      return percentText.map { "\($0) percent of Portkey budget \(state)" } ?? "Portkey budget \(state) unknown"
    }
    return gaugeMode == .spent
      ? percentText.map { "\($0) percent of credits spent" } ?? "Credits spent unknown"
      : percentText.map { "\($0) percent of credits remaining" } ?? "Credits remaining unknown"
  }

  var body: some View {
    let reduceMotion = reduceMotion
    let parts = parts
    let sweepStartFraction = gaugeMode.sweepStartFraction
    let accent = accent
    ZStack {
      Self.horseshoe(fraction: 1, color: accent.opacity(RunwayGlyph.trackOpacity))
      if isStatic {
        Self.arcs(parts: parts, color: accent)
      } else {
        // The animator only supplies the progress value. The arc is built from it, so the clear view is not shown.
        Color.clear
          .keyframeAnimator(initialValue: 0.0, trigger: openCount) { _, progress in
            let sweepProgress = reduceMotion ? 1 : progress
            let shownTotal = sweepStartFraction + (parts.total - sweepStartFraction) * sweepProgress
            Self.arcs(parts: Self.shownParts(target: parts, shownTotal: shownTotal), color: accent)
          } keyframes: { _ in
            LinearKeyframe(1.0, duration: Self.sweepDuration, timingCurve: .easeOut)
          }
          .animation(reduceMotion ? nil : .easeOut(duration: Self.refreshDuration), value: parts)
      }
      VStack(spacing: 0) {
        Text(hasNoBudget ? "--" : gaugePercent.map { "\($0)%" } ?? "--%")
          .bigFigureStyle()
        if !hasNoBudget {
          Text(gaugeMode == .spent ? "spent" : "left")
            .captionStyle()
        }
      }
    }
    .padding(Self.lineWidth / 2)
    .frame(width: Self.diameter, height: Self.diameter)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
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
        .bigFigureStyle(size: 15)
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

private struct FooterButtonStyle: ButtonStyle {
  let fillOpacity: Double

  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(isEnabled ? 1 : 0.4)
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
