import Foundation

public enum DashboardTab: String, CaseIterable, Sendable {
  case general
  case copilot
  case portkey

  public var title: String {
    switch self {
    case .general: "General"
    case .copilot: "Copilot"
    case .portkey: "Portkey"
    }
  }
}

public struct DashboardSidebarRow: Equatable, Sendable {
  public let tab: DashboardTab
  public let isEnabled: Bool
  public let status: String
  // nil when there is no real gauge to draw: loading, an error, an unlimited plan or no Portkey budget.
  public let gauge: GaugeTile?
  public let health: RunwayHealth

  public var accessibilityLabel: String { "\(tab.title), \(status)" }
}

public struct DashboardSidebarInput: Equatable, Sendable {
  public let copilotState: CopilotState
  public let copilotUsage: QuotaUsage?
  public let hasCopilotError: Bool
  public let combined: CombinedBudget?
  public let portkeySpentUSD: Double
  public let portkeyRequestCount: Int
  public let portkeyBudgetUSD: Double?
  // The Copilot cycle reset. nil while Copilot loads or after a first-launch network error.
  public let resetDate: Date?
  public let mode: GaugeMode
  public let days: RunwayDays

  public init(
    copilotState: CopilotState, copilotUsage: QuotaUsage?, hasCopilotError: Bool, combined: CombinedBudget?,
    portkeySpentUSD: Double, portkeyRequestCount: Int, portkeyBudgetUSD: Double?, resetDate: Date?, mode: GaugeMode,
    days: RunwayDays
  ) {
    self.copilotState = copilotState
    self.copilotUsage = copilotUsage
    self.hasCopilotError = hasCopilotError
    self.combined = combined
    self.portkeySpentUSD = portkeySpentUSD
    self.portkeyRequestCount = portkeyRequestCount
    self.portkeyBudgetUSD = portkeyBudgetUSD
    self.resetDate = resetDate
    self.mode = mode
    self.days = days
  }
}

// The Dashboard sidebar: which tabs it shows, what each row says, and how wide it is.
public enum DashboardSidebar {
  public static let openWidthRange: ClosedRange<Double> = 200...260
  public static let defaultWidth: Double = 220

  public static func restoredWidth(saved: Double?) -> Double {
    guard let saved else { return defaultWidth }
    return min(max(saved, openWidthRange.lowerBound), openWidthRange.upperBound)
  }

  public static func rows(_ input: DashboardSidebarInput, now: Date, locale: Locale = .current) -> [DashboardSidebarRow] {
    switch input.copilotState {
    case .copilot:
      let generalRow = copilotRow(.general, input: input, combined: input.combined, now: now, locale: locale)
      let copilotRow = copilotRow(.copilot, input: input, combined: nil, now: now, locale: locale)
      guard PortkeyBudget.showsBlock(requestCount: input.portkeyRequestCount, budgetUSD: input.portkeyBudgetUSD) else {
        return [generalRow, copilotRow]
      }
      return [generalRow, copilotRow, portkeyRow(input, now: now, locale: locale)]
    case .portkeyOnly:
      let portkeyRow = portkeyRow(input, now: now, locale: locale)
      let generalRow = DashboardSidebarRow(
        tab: .general, isEnabled: true, status: portkeyRow.status, gauge: portkeyRow.gauge, health: portkeyRow.health)
      let disabledCopilotRow = DashboardSidebarRow(
        tab: .copilot, isEnabled: false, status: "Copilot data is off", gauge: nil, health: .unavailable)
      return [generalRow, disabledCopilotRow, portkeyRow]
    case .noPortkeyData:
      return [DashboardSidebarRow(tab: .general, isEnabled: true, status: "Unavailable", gauge: nil, health: .unavailable)]
    }
  }

  public static func resolvedTab(saved: DashboardTab?, rows: [DashboardSidebarRow]) -> DashboardTab {
    guard let saved, rows.contains(where: { $0.tab == saved && $0.isEnabled }) else { return .general }
    return saved
  }

  // With combined, the row shows the combined budget in USD. Without it, the Copilot credits.
  private static func copilotRow(
    _ tab: DashboardTab, input: DashboardSidebarInput, combined: CombinedBudget?, now: Date, locale: Locale
  ) -> DashboardSidebarRow {
    if input.hasCopilotError {
      return DashboardSidebarRow(tab: tab, isEnabled: true, status: "Unavailable", gauge: nil, health: .unavailable)
    }
    guard let copilotUsage = input.copilotUsage else {
      return DashboardSidebarRow(tab: tab, isEnabled: true, status: "Loading", gauge: nil, health: .unavailable)
    }
    let health = RunwayHealth(usage: combined?.usage ?? copilotUsage, now: now, days: input.days)
    if copilotUsage.isUnlimited {
      return DashboardSidebarRow(tab: tab, isEnabled: true, status: "Unlimited", gauge: nil, health: health)
    }
    let gauge = GaugeTile.make(usage: copilotUsage, hasError: false, mode: input.mode, combined: combined)
    let amountText =
      if let combined {
        PortkeySpend.formatted(shownAmount(combined.usage, mode: input.mode), locale: locale)
      } else {
        "\(Credits.formatted(shownAmount(copilotUsage, mode: input.mode), locale: locale)) credits"
      }
    return DashboardSidebarRow(
      tab: tab, isEnabled: true, status: gaugeStatus(amountText: amountText, mode: input.mode, percent: gauge.percent),
      gauge: gauge, health: health)
  }

  // Portkey data is local, so a Copilot fetch error never makes this row unavailable.
  private static func portkeyRow(_ input: DashboardSidebarInput, now: Date, locale: Locale) -> DashboardSidebarRow {
    let resetDate = input.resetDate ?? PortkeyOnly.resetDate(now: now)
    guard
      let portkeyUsage = PortkeyBudget.usage(
        spentUSD: input.portkeySpentUSD, budgetUSD: input.portkeyBudgetUSD, resetDate: resetDate)
    else {
      return DashboardSidebarRow(
        tab: .portkey, isEnabled: true, status: "\(PortkeySpend.formatted(input.portkeySpentUSD, locale: locale)) spent",
        gauge: nil, health: .unavailable)
    }
    let gauge = GaugeTile.make(usage: portkeyUsage, hasError: false, mode: input.mode)
    let amountText = PortkeySpend.formatted(shownAmount(portkeyUsage, mode: input.mode), locale: locale)
    return DashboardSidebarRow(
      tab: .portkey, isEnabled: true, status: gaugeStatus(amountText: amountText, mode: input.mode, percent: gauge.percent),
      gauge: gauge, health: RunwayHealth(usage: portkeyUsage, now: now, days: input.days))
  }

  // Over the budget, the amount left stops at 0.
  static func shownAmount(_ usage: QuotaUsage, mode: GaugeMode) -> Double {
    switch mode {
    case .left: max(usage.creditsRemaining, 0)
    case .spent: usage.creditsUsed
    }
  }

  private static func gaugeStatus(amountText: String, mode: GaugeMode, percent: Int) -> String {
    let verb =
      switch mode {
      case .left: "left"
      case .spent: "spent"
      }
    return "\(amountText) \(verb) · \(percent)%"
  }
}
