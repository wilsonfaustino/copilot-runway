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
  let selection: DashboardSelection
  // The window controller owns the title bar: the tab title, the cycle dates and the Copy summary button.
  let chromeDidChange: (_ title: String, _ subtitle: String, _ canCopy: Bool) -> Void
  @AppStorage(Theme.taskPalettePreferenceKey) private var taskPalettePreference = TaskPalettePreference.unset
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiatesWithoutColor

  private var taskPalette: TaskPalette {
    TaskPalette.resolve(preference: taskPalettePreference, systemDifferentiatesWithoutColor: differentiatesWithoutColor)
  }

  private var chrome: [String] {
    [selection.tab.title, cycleSubtitle, usageStore.usage == nil ? "no usage" : "usage"]
  }

  var body: some View {
    tabContent(selection.tab)
      .frame(minWidth: 720, minHeight: 560)
      .onChange(of: chrome, initial: true) {
        chromeDidChange(selection.tab.title, cycleSubtitle, usageStore.usage != nil)
      }
  }

  // Each tab scrolls on its own, so the toolbar stays in place.
  private func tabContent(_ tab: DashboardTab) -> some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: Theme.Spacing.panel) {
        switch tab {
        case .general: generalTab
        case .copilot: copilotTab
        case .portkey: portkeyTab
        }
        if tab != .portkey, let sessionsWarning = usageStore.sessionsWarning {
          Text(sessionsWarning)
            .foregroundStyle(.orange)
        }
      }
      .padding(20)
      .background(OverlayScrollerStyle())
    }
    .scrollBounceBehavior(.basedOnSize)
    .id(tab)
  }

  private var copilotHealth: RunwayHealth {
    RunwayHealth(usage: usageStore.usage, hasError: usageStore.hasUsageError, now: .now, days: usageStore.runwayDays)
  }

  private var gaugeHealth: RunwayHealth {
    RunwayHealth(usage: usageStore.gaugeUsage, hasError: usageStore.hasUsageError, now: .now, days: usageStore.runwayDays)
  }

  @ViewBuilder
  private var generalTab: some View {
    switch usageStore.copilotState {
    case .copilot:
      if let usage = usageStore.usage {
        insightBanner(
          RunwayInsight.banner(
            usage: usage, errorMessage: usageStore.errorMessage, categoryCredits: usageStore.categoryCredits, now: .now,
            days: usageStore.runwayDays, combined: usageStore.combinedBudget
          ),
          health: gaugeHealth
        )
        HStack(alignment: .top, spacing: Theme.Spacing.regular) {
          runwayCard(usage: usageStore.gaugeUsage ?? usage, health: gaugeHealth)
          remainingCard(usage: usageStore.gaugeUsage ?? usage, health: gaugeHealth, combined: usageStore.combinedBudget)
          averageDailyBurnCard(usage: usage, combined: usageStore.combinedBudget)
          outcomesCard(usage: usage, showsUSD: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        dailyBurnChart(resetDate: usage.resetDate, health: gaugeHealth)
        providerCard(usage: usage)
        combinedTaskCard
        combinedModelAndAgentCards
      } else {
        errorText
      }
    case .portkeyOnly(let absence):
      if let resetDate = usageStore.cycleResetDate {
        insightBanner(
          RunwayInsight.portkeyOnlyBanner(
            usage: usageStore.gaugeUsage, spentUSD: usageStore.portkeySpend.totalUSD, absence: absence, now: .now,
            days: usageStore.runwayDays
          ),
          health: gaugeHealth
        )
        portkeyOnlyKPIRow(resetDate: resetDate, health: gaugeHealth)
        dailyBurnChart(resetDate: resetDate, health: gaugeHealth)
        combinedTaskCard
        combinedModelAndAgentCards
      }
    case .noPortkeyData:
      errorText
    }
  }

  // Copilot only: no combined budget, so the banner, the cards and the chart stay in credits.
  @ViewBuilder
  private var copilotTab: some View {
    if let usage = usageStore.usage {
      let health = copilotHealth
      insightBanner(
        RunwayInsight.banner(
          usage: usage, errorMessage: usageStore.errorMessage, categoryCredits: usageStore.categoryCredits, now: .now,
          days: usageStore.runwayDays, combined: nil
        ),
        health: health
      )
      HStack(alignment: .top, spacing: Theme.Spacing.regular) {
        runwayCard(usage: usage, health: health)
        remainingCard(usage: usage, health: health, combined: nil)
        averageDailyBurnCard(usage: usage, combined: nil)
        outcomesCard(usage: usage, showsUSD: false)
      }
      .fixedSize(horizontal: false, vertical: true)
      dailyBurnChart(resetDate: usage.resetDate, health: health, allowsUSD: false)
      HStack(alignment: .top, spacing: Theme.Spacing.regular) {
        taskCard
        modelCard(usage: usage)
        agentCard(usage: usage)
      }
      .fixedSize(horizontal: false, vertical: true)
      projectCard
      topSessionsCard
    } else {
      errorText
    }
  }

  // The Portkey cycle is the Copilot cycle, so it has a reset date also while Copilot loads.
  private var portkeyTab: some View {
    portkeySection(resetDate: usageStore.cycleResetDate ?? PortkeyOnly.resetDate(now: .now))
  }

  private var errorText: some View {
    Text(usageStore.errorMessage ?? "Loading usage from GitHub.")
      .foregroundStyle(.secondary)
  }

  private var cycleSubtitle: String {
    if usageStore.isPortkeyOnly, let resetDate = usageStore.cycleResetDate {
      return "Portkey only · \(cycleRange(resetDate: resetDate))"
    }
    guard let usage = usageStore.usage else { return "" }
    return "Cycle \(cycleRange(resetDate: usage.resetDate))"
  }

  private func cycleRange(resetDate: Date) -> String {
    let cycleStart = Runway.cycleStart(resetDate: resetDate)
    let lastCycleDay = Runway.lastCycleDay(resetDate: resetDate)
    return "\(day(cycleStart)) to \(day(lastCycleDay)) · resets \(day(resetDate))"
  }

  // MARK: Insight banner

  private func insightBanner(_ text: (headline: String, detail: String), health: RunwayHealth) -> some View {
    let accent = Theme.accent(health)
    let (headline, detail) = text
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
    if usageStore.hasUsageError, let usageError = usageStore.usageError { return RunwayGlyph.menuBarSymbolName(error: usageError) }
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

  private func runwayCard(
    usage: QuotaUsage, health: RunwayHealth, figureSize: CGFloat = 34, lastsTheCycle: Bool? = nil
  ) -> some View {
    kpiCard("Runway") {
      if usage.isUnlimited {
        Text("∞").bigFigureStyle(size: 34)
        kpiDetail("Unlimited plan")
      } else if lastsTheCycle ?? Runway.lastsTheCycle(usage: usage, now: .now, days: usageStore.runwayDays) {
        Text("Lasts the cycle")
          .bigFigureStyle(size: 22)
          .foregroundStyle(Theme.accent(health))
        kpiDetail(RunwayInsight.resetCaption(usage: usage))
      } else if let wholeDays = Runway.wholeDaysLeft(usage: usage, now: .now, days: usageStore.runwayDays),
        let runOutDate = Runway.runOutDate(usage: usage, now: .now, days: usageStore.runwayDays)
      {
        Text("\(wholeDays) \(usageStore.runwayDays.dayWord(count: wholeDays))")
          .bigFigureStyle(size: figureSize)
          .foregroundStyle(Theme.accent(health))
        kpiDetail("Run-out \(day(max(runOutDate, .now)))")
      } else {
        Text("--").bigFigureStyle(size: figureSize)
        kpiDetail("No burn yet")
      }
    }
  }

  private func remainingCard(usage: QuotaUsage, health: RunwayHealth, combined: CombinedBudget?) -> some View {
    let gaugeMode = usageStore.gaugeMode
    return kpiCard(gaugeMode == .spent ? "Spent" : "Remaining") {
      if usage.isUnlimited {
        Text("Unlimited").bigFigureStyle(size: 34)
        kpiDetail("\(Credits.formatted(usage.creditsUsed)) used")
      } else {
        Text("\(Runway.wholeGaugePercent(usage: usage, mode: gaugeMode))%").bigFigureStyle(size: 34)
        if combined != nil {
          let accent = Theme.accent(health)
          combinedBar(parts: usageStore.gaugeParts, color: accent)
          kpiDetail("\(PortkeySpend.formatted(usage.creditsUsed)) of \(PortkeySpend.formatted(usage.entitlement)) used")
        } else {
          shareBar(fraction: MenuBarTitle.gaugeFraction(usage: usage, mode: gaugeMode), color: Theme.accent(health))
          kpiDetail("\(Credits.formatted(usage.creditsUsed)) of \(Credits.formatted(usage.entitlement)) used")
        }
      }
    }
  }

  // In USD for a combined budget, else in Copilot credits.
  private func averageDailyBurnCard(usage: QuotaUsage, combined: CombinedBudget?) -> some View {
    let runwayDays = usageStore.runwayDays
    return kpiCard("Average daily burn") {
      if let combined {
        Text(PortkeySpend.formatted(Runway.averageDailyBurn(usage: combined.usage, now: .now, days: runwayDays)))
          .bigFigureStyle(size: 34)
        kpiDetail("USD per \(runwayDays.dayWord())")
      } else {
        Text(Credits.formatted(Runway.averageDailyBurn(usage: usage, now: .now, days: runwayDays)))
          .bigFigureStyle(size: 34)
        kpiDetail("credits per \(runwayDays.dayWord())")
      }
    }
  }

  // General shows cost per PR in USD, the Copilot tab shows credits per PR authored.
  private func outcomesCard(usage: QuotaUsage, showsUSD: Bool) -> some View {
    let title = showsUSD ? "Cost per PR" : "Credits per PR authored"
    return kpiCard(title) {
      if usageStore.organization == nil {
        Text("--").bigFigureStyle(size: 34)
        Text("Set a GitHub organization in Settings to see \(showsUSD ? "cost per PR" : "credits per PR authored").")
          .font(.system(size: 12))
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
        Button("Open Settings") {
          usageStore.settingsTab = .sources
          SettingsWindowController.show(usageStore: usageStore)
        }
        .buttonStyle(.link)
        .controlSize(.small)
      } else {
        if let outcomes = usageStore.outcomes {
          if showsUSD {
            let combined = usageStore.combinedBudget
            Text(
              outcomes.usdPerPRAuthored(copilotCreditsUsed: usage.creditsUsed, combined: combined).map { PortkeySpend.formatted($0) }
                ?? "No PRs yet"
            )
            .bigFigureStyle(size: 34)
            kpiDetail("\(GitHubOutcomes.countText(outcomes.prsMerged)) merged · \(GitHubOutcomes.countText(outcomes.prsOpen)) open")
              .lineLimit(1)
              .minimumScaleFactor(0.85)
              .help(
                "Spend this cycle (\(combined == nil ? "Copilot only" : "Copilot plus Portkey")) divided by the merged and open PRs you created this cycle. Closed PRs that were not merged are not counted."
              )
          } else {
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
          }
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

  // With no budget there is no runway, so Spent takes the place of Left.
  private func portkeyOnlyKPIRow(resetDate: Date, health: RunwayHealth) -> some View {
    let spend = usageStore.portkeySpend
    let runwayDays = usageStore.runwayDays
    return HStack(alignment: .top, spacing: Theme.Spacing.regular) {
      if let budgetUsage = usageStore.gaugeUsage {
        runwayCard(usage: budgetUsage, health: health)
        kpiCard("Left") {
          Text(PortkeySpend.formatted(max(budgetUsage.creditsRemaining, 0))).bigFigureStyle(size: 34)
          shareBar(fraction: MenuBarTitle.gaugeFraction(usage: budgetUsage, mode: .left), color: Theme.accent(health))
          kpiDetail(
            "of \(PortkeySpend.formatted(budgetUsage.entitlement)), \(Runway.wholeGaugePercent(usage: budgetUsage, mode: .left))%"
          )
        }
      } else {
        kpiCard("Runway") {
          Text("--").bigFigureStyle(size: 34)
          Button("Set a monthly budget to see runway") {
            usageStore.settingsTab = .sources
            SettingsWindowController.show(usageStore: usageStore)
          }
          .buttonStyle(.link)
          .font(.system(size: 12))
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
        }
        kpiCard("Spent") {
          Text(PortkeySpend.formatted(spend.totalUSD)).bigFigureStyle(size: 34)
          kpiDetail("this month")
        }
      }
      kpiCard("Average daily burn") {
        Text(PortkeySpend.formatted(Runway.averageDailyBurn(credits: spend.totalUSD, resetDate: resetDate, now: .now, days: runwayDays)))
          .bigFigureStyle(size: 34)
        kpiDetail("USD per \(runwayDays.dayWord())")
      }
      kpiCard("Requests") {
        Text("\(spend.requestCount)").bigFigureStyle(size: 34)
        if let averageUSDPerRequest = spend.averageUSDPerRequest {
          kpiDetail("\(PortkeySpend.formatted(averageUSDPerRequest)) each")
        }
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: By provider

  // Each bar measures its own budget. Copilot takes the full accent and Portkey the 0.6 tone, as in the gauges.
  private func providerCard(usage: QuotaUsage) -> some View {
    let accent = Theme.accent(gaugeHealth)
    let rows = ProviderRows.rows(
      copilotUsage: usage, portkeySpend: usageStore.portkeySpend, portkeyBudgetUSD: usageStore.portkeyBudgetUSD,
      mode: usageStore.gaugeMode, days: usageStore.runwayDays, now: .now)
    return VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      Text("By provider")
        .font(Self.cardTitleFont)
      ForEach(rows, id: \.tab) { row in
        Button {
          selection.tab = row.tab
          selection.chosenTab = row.tab
          DashboardDefaults.save(row.tab.rawValue, forKey: DashboardDefaults.tabKey)
        } label: {
          providerRowView(row, color: row.tab == .portkey ? accent.opacity(RunwayGlyph.portkeyOpacity) : accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityHint("Opens the \(row.tab.title) tab")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardStyle(padding: Theme.Spacing.panel)
  }

  private func providerRowView(_ row: ProviderRow, color: Color) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      HStack(alignment: .firstTextBaseline) {
        Text(row.tab.title)
          .font(.system(size: 12, weight: .medium))
        Spacer()
        kpiDetail(row.amountText)
        kpiDetail(row.burnText)
          .foregroundStyle(.secondary)
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      if let barFraction = row.barFraction {
        shareBar(fraction: barFraction, color: color)
      }
    }
    .contentShape(Rectangle())
  }

  // MARK: Share cards

  private var taskColors: [ShareItem.ID: Color] {
    Dictionary(uniqueKeysWithValues: TaskCategory.allCases.map { (.entry($0.displayName), Theme.taskColor($0, palette: taskPalette)) })
  }

  private var taskCard: some View {
    shareCard(
      title: "By task",
      breakdown: ShareBreakdown.tasks(usageStore.categoryCredits),
      colors: taskColors,
      marksSmallShares: true
    )
  }

  // General: Copilot and Portkey in USD. In Portkey only mode categoryCredits is empty, so the card shows Portkey alone.
  private var combinedTaskCard: some View {
    shareCard(
      title: "By task",
      breakdown: CombinedTaskSpend.breakdown(copilot: usageStore.categoryCredits, portkeyRecords: usageStore.portkeySpend.records),
      colors: taskColors,
      marksSmallShares: true
    )
  }

  // General: Copilot and Portkey in USD, priced spend only.
  private var combinedModelAndAgentCards: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.regular) {
      combinedModelCard
      combinedAgentCard
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  // The notes also show with no priced spend, because they explain the empty text.
  private var combinedModelCard: some View {
    let breakdown = CombinedBreakdown.models(copilot: usageStore.modelCredits, portkey: usageStore.portkeySpend)
    var footnotes: [String] = []
    if usageStore.modelCredits.contains(where: \.isMissingPrice) {
      footnotes.append("Copilot: some messages have no price, so the total misses them.")
    }
    if let unpricedNote = usageStore.portkeySpend.unpricedNote {
      footnotes.append("Portkey: " + unpricedNote)
    }
    return shareCard(
      title: "By model", breakdown: breakdown, colors: Theme.modelColors(for: breakdown), footnotes: footnotes, showsFullNameOnHover: true
    )
  }

  // Portkey-only mode empties sourceCredits, so the colors also come from the Portkey sources.
  private var combinedAgentCard: some View {
    let sources = Set(usageStore.sourceCredits.map(\.source) + usageStore.portkeySpend.bySource.map(\.source))
    return shareCard(
      title: "By agent",
      breakdown: CombinedBreakdown.agents(copilot: usageStore.sourceCredits, portkey: usageStore.portkeySpend),
      colors: Dictionary(uniqueKeysWithValues: sources.map { (.entry($0.displayName), Theme.agentColor($0)) })
    )
  }

  private func modelCard(usage: QuotaUsage) -> some View {
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

  private func agentCard(usage: QuotaUsage) -> some View {
    let sourceCredits = usageStore.sourceCredits
    let breakdown = ShareBreakdown.local(entries: sourceCredits.map { ($0.source.displayName, $0.credits) })
    let creditsPerDay = sourceCredits.map { source in
      "\(source.source.displayName): \(Credits.formatted(Runway.averageDailyBurn(credits: source.credits, resetDate: usage.resetDate, now: .now, days: usageStore.runwayDays))) credits/\(usageStore.runwayDays.dayWord())."
    }
    return shareCard(
      title: "By agent",
      breakdown: breakdown,
      colors: Dictionary(uniqueKeysWithValues: sourceCredits.map { (.entry($0.source.displayName), Theme.agentColor($0.source)) }),
      footnotes: creditsPerDay.isEmpty ? [] : [creditsPerDay.joined(separator: " ")]
    )
  }

  private var projectCard: some View {
    let breakdown = ProjectName.breakdown(usageStore.projectCredits)
    let projectCount = usageStore.projectCredits.count
    return shareCard(
      title: "By project",
      breakdown: breakdown,
      colors: Theme.projectColors(for: breakdown),
      insight: ProjectName.insight(breakdown),
      footnotes: breakdown.isEmpty
        ? []
        : ["\(projectCount == 1 ? "1 project" : "\(projectCount) projects"). Named from the repo root, so worktree sessions count with their repo."]
    )
  }

  // MARK: Portkey

  @ViewBuilder
  private func portkeySection(resetDate: Date) -> some View {
    let spend = usageStore.portkeySpend
    if PortkeyBudget.showsBlock(requestCount: spend.requestCount, budgetUSD: usageStore.portkeyBudgetUSD) {
      PortkeyDashboardSection(
        spend: spend,
        budgetStatus: PortkeyBudget.status(
          spentUSD: spend.totalUSD, budgetUSD: usageStore.portkeyBudgetUSD, resetDate: resetDate, now: .now, days: usageStore.runwayDays
        ),
        dateRange: "\(day(Runway.cycleStart(resetDate: resetDate))) to \(day(.now))",
        isPortkeyOnly: usageStore.isPortkeyOnly,
        runwayCard: portkeyRunwayCard(resetDate: resetDate),
        dailySpendChart: portkeyDailySpendChart(resetDate: resetDate),
        breakdownCards: portkeyBreakdownCards
      )
    }
  }

  // Portkey records only, in USD.
  private var portkeyBreakdownCards: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.regular) {
      shareCard(
        title: "By task",
        breakdown: CombinedTaskSpend.breakdown(copilot: [], portkeyRecords: usageStore.portkeySpend.records),
        colors: taskColors,
        marksSmallShares: true
      )
      portkeyProjectCard
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  // No insight line, because ProjectName.insight speaks of local credits.
  private var portkeyProjectCard: some View {
    let projects = ProjectName.breakdown(usageStore.portkeyByProject)
    let breakdown = ShareBreakdown(shareTotal: projects.shareTotal, items: projects.items, unit: ShareBreakdown.localUSDUnit, isUSD: true)
    let projectCount = usageStore.portkeyByProject.count
    return shareCard(
      title: "By project",
      breakdown: breakdown,
      colors: Theme.projectColors(for: breakdown),
      footnotes: breakdown.isEmpty
        ? []
        : ["\(projectCount == 1 ? "1 project" : "\(projectCount) projects"). Named from the repo root, so worktree sessions count with their repo."]
    )
  }

  // The Portkey budget alone, never the combined or Copilot usage, so a Copilot error does not change its tone.
  @ViewBuilder
  private func portkeyRunwayCard(resetDate: Date) -> some View {
    if let budgetUsage = PortkeyBudget.usage(
      spentUSD: usageStore.portkeySpend.totalUSD, budgetUSD: usageStore.portkeyBudgetUSD, resetDate: resetDate
    ) {
      runwayCard(
        usage: budgetUsage, health: RunwayHealth(usage: budgetUsage, now: .now, days: usageStore.runwayDays), figureSize: 26,
        lastsTheCycle: PortkeyBudget.lastsTheCycle(
          usage: budgetUsage, requestCount: usageStore.portkeySpend.requestCount, now: .now, days: usageStore.runwayDays
        )
      )
    } else {
      kpiCard("Runway") {
        Text("--").bigFigureStyle(size: 26)
        kpiDetail("No budget set")
      }
    }
  }

  // Portkey USD per UTC day, the last cycle line and the budget pace line. Copilot days are only the day list.
  private func portkeyDailySpendChart(resetDate: Date) -> some View {
    let spend = usageStore.portkeySpend
    let days = CombinedDailyBurn.days(copilot: usageStore.dailyCredits, portkeyRecords: spend.records)
      .map { DailyCredits(day: $0.day, credits: $0.portkeyUSD) }
    let previousTotals = CombinedDailyBurn.days(
      copilot: usageStore.previousDailyCredits, portkeyRecords: usageStore.previousPortkeySpend.records
    )
    .map { DailyCredits(day: $0.day, credits: $0.portkeyUSD) }
    let budgetUsage = PortkeyBudget.usage(spentUSD: spend.totalUSD, budgetUSD: usageStore.portkeyBudgetUSD, resetDate: resetDate)
    return DailyBurnChart(
      days: days.map { DailyBurnChart.ChartDay(day: $0.day, copilot: 0, portkey: $0.credits) },
      previousTotals: previousTotals,
      comparisonSentence: nil,
      cycleDayCount: Runway.cycleDayCount(resetDate: resetDate),
      averageDailyBurn: nil,
      unit: .usd,
      title: "Daily spend",
      budgetPace: PortkeyBudget.dailyPaceUSD(
        spentUSD: spend.totalUSD, budgetUSD: usageStore.portkeyBudgetUSD, resetDate: resetDate, now: .now
      ),
      runwayDays: usageStore.runwayDays,
      health: budgetUsage.map { RunwayHealth(usage: $0, now: .now, days: usageStore.runwayDays) } ?? .healthy,
      isPortkeyOnly: true
    )
  }

  // MARK: Top sessions

  private var topSessionsCard: some View {
    let sessions = usageStore.sessionSpends
    let localTotal = sessions.reduce(0) { $0 + $1.credits }
    let topSessions = Array(sessions.prefix(SessionSpend.topCount))
    // A session bar takes its project's color, gray when the project folds into "Other projects".
    let projectColors = Theme.projectColors(for: ProjectName.breakdown(usageStore.projectCredits))
    return VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
        Text("Top sessions")
          .font(Self.cardTitleFont)
        Spacer()
        if !topSessions.isEmpty {
          Text("\(SessionSpend.topShare(sessions, of: localTotal))%")
            .bigFigureStyle(size: 26)
          Text("of credits in \(topSessions.count == 1 ? "1 session" : "\(topSessions.count) sessions")")
            .captionStyle()
        }
      }
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      if let topSentence = SessionSpend.topSentence(sessions) {
        Text(topSentence)
          .font(.system(size: 12.5))
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
          ForEach(Array(topSessions.enumerated()), id: \.offset) { index, session in
            sessionRow(
              rank: index + 1, session: session, localTotal: localTotal, topCredits: topSessions[0].credits,
              color: projectColors[.entry(session.project)] ?? Theme.otherModelsColor
            )
          }
        }
        Text("Labels use date, agent, top model and biggest task. No prompt text or titles. This cycle only.")
          .captionStyle()
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("No local sessions in this cycle.")
          .captionStyle()
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .cardStyle(padding: Theme.Spacing.panel)
  }

  // The bar is scaled to the top session, so the first row is always full width.
  private func sessionRow(rank: Int, session: SessionSpend, localTotal: Double, topCredits: Double, color: Color) -> some View {
    let label = session.label()
    let turns = session.turnCount == 1 ? "1 turn" : "\(session.turnCount) turns"
    let share = session.sharePercentText(of: localTotal)
    return VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
      HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.regular) {
        Text("\(rank)")
          .foregroundStyle(.secondary)
          .frame(width: 14, alignment: .trailing)
        VStack(alignment: .leading, spacing: 2) {
          Text(label)
          Text("\(session.project) · \(turns)")
            .captionStyle()
        }
        Spacer()
        Text(Credits.formatted(session.credits))
        Text(share)
          .foregroundStyle(.secondary)
          .frame(minWidth: 48, alignment: .trailing)
      }
      .font(.system(size: 12.5))
      .monospacedDigit()
      .lineLimit(1)
      shareBar(fraction: topCredits > 0 ? session.credits / topCredits : 0, color: color)
        .padding(.leading, 14 + Theme.Spacing.regular)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(rank). \(label), \(session.project), \(turns)")
    .accessibilityValue("\(Credits.formatted(session.credits)) credits, \(share) of local credits")
  }

  // Items without a color in colors are the folded "Other models" item. A task split draws one bar per model instead.
  private func shareCard(
    title: String,
    breakdown: ShareBreakdown,
    colors: [ShareItem.ID: Color],
    insight: String? = nil,
    taskSplit: ModelTaskSplit? = nil,
    footnotes: [String] = [],
    marksSmallShares: Bool = false,
    notInLocalSessionsNote: String? = nil,
    showsFullNameOnHover: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
        Text(title)
          .font(Self.cardTitleFont)
        Spacer()
        Text(breakdown.formattedAmount(breakdown.shareTotal))
          .bigFigureStyle(size: 26)
        Text(breakdown.unit)
          .captionStyle()
      }
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      if let insight {
        Text(insight)
          .font(.system(size: 12.5))
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      if !breakdown.isEmpty, let taskSplit {
        ModelTaskSplitView(
          breakdown: breakdown, taskSplit: taskSplit, taskPalette: taskPalette, notInLocalSessionsNote: notInLocalSessionsNote
        )
      } else if !breakdown.isEmpty {
        ShareBreakdownView(
          breakdown: breakdown, colors: colors, marksSmallShares: marksSmallShares, notInLocalSessionsNote: notInLocalSessionsNote,
          highlightsOnHover: true, showsFullNameOnHover: showsFullNameOnHover
        )
      } else {
        Text(breakdown.isUSD ? "No priced spend in this cycle." : "No local sessions in this cycle.")
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

  private func combinedBar(parts: GaugeParts, color: Color) -> some View {
    RoundedRectangle(cornerRadius: Theme.Radius.bar)
      .fill(color.opacity(RunwayGlyph.trackOpacity))
      .frame(height: 6)
      .overlay(alignment: .leading) {
        GeometryReader { proxy in
          if parts.portkey > 0 {
            RoundedRectangle(cornerRadius: Theme.Radius.bar)
              .fill(color.opacity(RunwayGlyph.portkeyOpacity))
              .frame(width: proxy.size.width * min(max(parts.total, 0), 1))
          }
          RoundedRectangle(cornerRadius: Theme.Radius.bar)
            .fill(color)
            .frame(width: proxy.size.width * min(max(parts.copilot, 0), 1))
        }
      }
  }

  // The USD form for Portkey only and for a combined budget, else the credits form. allowsUSD false forces credits.
  private func dailyBurnChart(resetDate: Date, health: RunwayHealth, allowsUSD: Bool = true) -> some View {
    let cycleDayCount = Runway.cycleDayCount(resetDate: resetDate)
    let usdAverageDailyBurn: Double? =
      if !allowsUSD {
        nil
      } else if usageStore.isPortkeyOnly {
        usageStore.gaugeUsage.map { Runway.averageDailyBurn(usage: $0, now: .now, days: usageStore.runwayDays) }
          ?? Runway.averageDailyBurn(
            credits: usageStore.portkeySpend.totalUSD, resetDate: resetDate, now: .now, days: usageStore.runwayDays)
      } else {
        usageStore.combinedBudget.map { Runway.averageDailyBurn(usage: $0.usage, now: .now, days: usageStore.runwayDays) }
      }
    if let usdAverageDailyBurn {
      let days = CombinedDailyBurn.days(copilot: usageStore.dailyCredits, portkeyRecords: usageStore.portkeySpend.records)
      let previousDays = CombinedDailyBurn.days(
        copilot: usageStore.previousDailyCredits, portkeyRecords: usageStore.previousPortkeySpend.records
      )
      let previousTotals = previousDays.map { DailyCredits(day: $0.day, credits: $0.totalUSD) }
      let comparison = CycleComparison.compare(
        current: days.map { DailyCredits(day: $0.day, credits: $0.totalUSD) }, previous: previousTotals
      )
      return DailyBurnChart(
        days: days.map { DailyBurnChart.ChartDay(day: $0.day, copilot: $0.copilotUSD, portkey: $0.portkeyUSD) },
        previousTotals: previousTotals,
        comparisonSentence: comparison?.sentence(unit: .usd),
        cycleDayCount: cycleDayCount,
        averageDailyBurn: usdAverageDailyBurn,
        unit: .usd,
        runwayDays: usageStore.runwayDays,
        health: health,
        isPortkeyOnly: usageStore.isPortkeyOnly
      )
    }
    return DailyBurnChart(
      days: usageStore.dailyCredits.map { DailyBurnChart.ChartDay(day: $0.day, copilot: $0.credits, portkey: 0) },
      previousTotals: usageStore.previousDailyCredits,
      comparisonSentence: usageStore.cycleComparisonSentence,
      cycleDayCount: cycleDayCount,
      averageDailyBurn: usageStore.usage.map { Runway.averageDailyBurn(usage: $0, now: .now, days: usageStore.runwayDays) } ?? 0,
      unit: .credits,
      runwayDays: usageStore.runwayDays,
      health: health
    )
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

  // Values are in credits for the credits form, or USD for the combined form. portkey is 0 in credits.
  struct ChartDay {
    let day: Date
    let copilot: Double
    let portkey: Double
    var total: Double { copilot + portkey }
  }

  static let portkeyBarColor = DashboardView.barColor.opacity(0.45)

  let days: [ChartDay]
  // One total per day of the last cycle, in the same unit as days.
  let previousTotals: [DailyCredits]
  let comparisonSentence: String?
  let cycleDayCount: Int
  // nil hides the average line.
  let averageDailyBurn: Double?
  let unit: BudgetUnit
  var title = "Daily burn"
  // The budget left per day to the reset, in USD. nil hides the pace line.
  var budgetPace: Double?

  // Half a credit in either unit, so the invisible hover mark never stretches the y axis past the data.
  private var hoverMarkPadding: Double {
    unit == .usd ? 0.005 : 0.5
  }
  let runwayDays: RunwayDays
  let health: RunwayHealth
  // Portkey only has no Copilot series, so the Portkey bars take the full bar color and no text names Copilot.
  var isPortkeyOnly = false
  @State private var selectedDayPosition: Double?

  private var portkeyColor: Color {
    isPortkeyOnly ? DashboardView.barColor : Self.portkeyBarColor
  }

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
    let copilotTotal = days.reduce(0) { $0 + $1.copilot }
    let portkeyTotal = days.reduce(0) { $0 + $1.portkey }
    let previousTotal = previousTotals.reduce(0) { $0 + $1.credits }
    let averageName = isPortkeyOnly ? "Portkey average" : unit == .usd ? "Combined average" : "GitHub average"
    let showsPreviousCycle = previousTotal > 0
    let averageColor = Theme.accent(health)
    let dayCount = max(cycleDayCount, days.count, showsPreviousCycle ? previousTotals.count : 0)
    let selectedIndex = selectedDayPosition.map { min(max(Int($0.rounded()), 1), dayCount) - 1 }
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.regular) {
          Text(title)
            .font(DashboardView.cardTitleFont)
          Text("Days are UTC.")
            .captionStyle()
          Spacer()
          HStack(spacing: Theme.Spacing.panel) {
            if !isPortkeyOnly {
              HStack(spacing: Theme.Spacing.small) {
                RoundedRectangle(cornerRadius: 2)
                  .fill(DashboardView.barColor)
                  .frame(width: 10, height: 10)
                Text(unit == .usd ? "Copilot, \(amount(copilotTotal)) local" : "This cycle, \(amount(copilotTotal)) local credits")
              }
            }
            if unit == .usd {
              HStack(spacing: Theme.Spacing.small) {
                RoundedRectangle(cornerRadius: 2)
                  .fill(portkeyColor)
                  .frame(width: 10, height: 10)
                Text("Portkey, \(amount(portkeyTotal))")
              }
            }
            if showsPreviousCycle {
              HStack(spacing: Theme.Spacing.small) {
                legendLine(color: Self.previousLineColor, style: Self.previousLineStyle)
                Text(unit == .usd ? "Last cycle, \(amount(previousTotal))" : "Last cycle, \(amount(previousTotal)) local credits")
              }
            }
            if let averageDailyBurn {
              HStack(spacing: Theme.Spacing.small) {
                legendLine(color: averageColor, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                Text("\(averageName), \(amount(averageDailyBurn))/\(runwayDays.dayWord())")
              }
            }
            if let budgetPace {
              HStack(spacing: Theme.Spacing.small) {
                legendLine(color: averageColor, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                Text("Budget pace, \(amount(budgetPace))/day")
              }
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
        ForEach(Array(days.enumerated()), id: \.offset) { index, chartDay in
          let dayName = chartDay.day.formatted(DashboardView.dayLabelStyle)
          if !isPortkeyOnly {
            RectangleMark(
              xStart: .value("Day start", Self.dayPosition(index) - Self.barHalfWidth),
              xEnd: .value("Day end", Self.dayPosition(index) + Self.barHalfWidth),
              yStart: .value("Baseline", 0.0),
              yEnd: .value(unit == .usd ? "Copilot USD" : "Credits", chartDay.copilot)
            )
            .foregroundStyle(DashboardView.barColor)
            .cornerRadius(4)
            .accessibilityLabel(unit == .usd ? "This cycle, \(dayName), Copilot" : "This cycle, \(dayName)")
            .accessibilityValue(unit == .usd ? amount(chartDay.copilot) : "\(amount(chartDay.copilot)) local credits")
          }
          if chartDay.portkey > 0 {
            RectangleMark(
              xStart: .value("Day start", Self.dayPosition(index) - Self.barHalfWidth),
              xEnd: .value("Day end", Self.dayPosition(index) + Self.barHalfWidth),
              yStart: .value("Copilot USD", chartDay.copilot),
              yEnd: .value("Total USD", chartDay.total)
            )
            .foregroundStyle(portkeyColor)
            .cornerRadius(4)
            .accessibilityLabel("This cycle, \(dayName), Portkey")
            .accessibilityValue(amount(chartDay.portkey))
          }
        }
        if showsPreviousCycle {
          ForEach(Array(previousTotals.enumerated()), id: \.offset) { index, dayCredits in
            LineMark(
              x: .value("Day", Self.dayPosition(index)),
              y: .value("Last cycle total", dayCredits.credits)
            )
            .foregroundStyle(Self.previousLineColor)
            .lineStyle(Self.previousLineStyle)
            .accessibilityHidden(true)
            // The line is exposed as undated segments, so an invisible mark carries each day's label.
            // A rectangle, like the bars, because Charts folds point marks of one series into those segments too.
            RectangleMark(
              xStart: .value("Day start", Self.dayPosition(index) - 0.05),
              xEnd: .value("Day end", Self.dayPosition(index) + 0.05),
              yStart: .value("Last cycle start", max(dayCredits.credits - hoverMarkPadding, 0)),
              yEnd: .value("Last cycle credits", dayCredits.credits + hoverMarkPadding)
            )
            .opacity(0)
            .accessibilityLabel("Last cycle, \(dayCredits.day.formatted(DashboardView.dayLabelStyle))")
            .accessibilityValue(unit == .usd ? amount(dayCredits.credits) : "\(amount(dayCredits.credits)) local credits")
          }
        }
        if let averageDailyBurn {
          RuleMark(y: .value(averageName, averageDailyBurn))
            .foregroundStyle(averageColor)
            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            .accessibilityLabel(averageName)
            .accessibilityValue(unit == .usd ? "\(amount(averageDailyBurn)) per \(runwayDays.dayWord())" : "\(amount(averageDailyBurn)) credits per \(runwayDays.dayWord())")
        }
        if let budgetPace {
          RuleMark(y: .value("Budget pace", budgetPace))
            .foregroundStyle(averageColor)
            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            .accessibilityLabel("Budget pace")
            .accessibilityValue("\(amount(budgetPace)) per day")
        }
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
      .chartYAxis {
        if unit == .usd {
          AxisMarks { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
              if let usd = value.as(Double.self) { Text(PortkeySpend.formatted(usd)) }
            }
          }
        } else {
          AxisMarks()
        }
      }
      .frame(height: 200)
      .accessibilityLabel(title)
      .accessibilityValue(accessibilitySummary(copilotTotal: copilotTotal, portkeyTotal: portkeyTotal, previousTotal: previousTotal))
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
    if days.indices.contains(index) {
      lines.append(hoverLine(days[index]))
    }
    if showsPreviousCycle, previousTotals.indices.contains(index) {
      lines.append(hoverLine(previousTotals[index]))
    }
    return Text(lines.joined(separator: "\n"))
      .font(.caption)
      .monospacedDigit()
      .padding(6)
      .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
      .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Color.primary.opacity(0.2)))
  }

  // The USD form splits the bar total, like "Nov 3: $13.25 ($12.00 Copilot, $1.25 Portkey)".
  private func hoverLine(_ chartDay: ChartDay) -> String {
    let dayName = chartDay.day.formatted(DashboardView.dayLabelStyle)
    guard unit == .usd else { return "\(dayName): \(amount(chartDay.total)) credits" }
    if isPortkeyOnly { return "\(dayName): \(amount(chartDay.portkey))" }
    return "\(dayName): \(amount(chartDay.total)) (\(amount(chartDay.copilot)) Copilot, \(amount(chartDay.portkey)) Portkey)"
  }

  private func hoverLine(_ dayTotal: DailyCredits) -> String {
    let dayName = dayTotal.day.formatted(DashboardView.dayLabelStyle)
    return "\(dayName): \(amount(dayTotal.credits))" + (unit == .usd ? "" : " credits")
  }

  private func amount(_ value: Double) -> String {
    unit == .usd ? PortkeySpend.formatted(value) : Credits.formatted(value)
  }

  private func accessibilitySummary(copilotTotal: Double, portkeyTotal: Double, previousTotal: Double) -> String {
    var sentences: [String]
    if isPortkeyOnly {
      sentences = ["This cycle, \(amount(portkeyTotal)) Portkey over \(days.count) days."]
    } else if unit == .usd {
      sentences = ["This cycle, \(amount(copilotTotal)) Copilot and \(amount(portkeyTotal)) Portkey over \(days.count) days."]
    } else {
      sentences = ["This cycle, \(amount(copilotTotal)) local credits over \(days.count) days."]
    }
    if previousTotal > 0 {
      sentences.append(unit == .usd ? "Last cycle, \(amount(previousTotal))." : "Last cycle, \(amount(previousTotal)) local credits.")
    }
    if let comparisonSentence { sentences.append(comparisonSentence) }
    return sentences.joined(separator: " ")
  }
}
