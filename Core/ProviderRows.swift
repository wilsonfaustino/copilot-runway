import Foundation

public struct ProviderRow: Equatable, Sendable {
  public let tab: DashboardTab
  public let amountText: String
  // nil when there is no budget to measure against: an unlimited Copilot plan or no Portkey budget.
  public let barFraction: Double?
  public let burnAmountText: String
  public let dayWord: String

  public var burnText: String { "\(burnAmountText)/\(dayWord)" }
  public var accessibilityLabel: String { "\(tab.title), \(amountText), \(burnAmountText) per \(dayWord)" }
}

// The By provider card on the General tab: one row per provider, each with its own budget, in USD.
public enum ProviderRows {
  public static func rows(
    copilotUsage: QuotaUsage, portkeySpentUSD: Double, portkeyRequestCount: Int,
    portkeyBudgetUSD: Double?, mode: GaugeMode, days: RunwayDays, now: Date, locale: Locale = .current
  ) -> [ProviderRow] {
    let resetDate = copilotUsage.resetDate
    let copilotSpentUSD = copilotUsage.creditsUsed * Credits.usdPerCredit
    let copilotRow =
      if copilotUsage.isUnlimited {
        row(.copilot, amountText: "\(PortkeySpend.formatted(copilotSpentUSD, locale: locale)) spent", barFraction: nil,
          spentUSD: copilotSpentUSD, resetDate: resetDate, days: days, now: now, locale: locale)
      } else {
        row(
          .copilot,
          amountText: budgetText(
            shownUSD: DashboardSidebar.shownAmount(copilotUsage, mode: mode) * Credits.usdPerCredit,
            budgetUSD: copilotUsage.entitlement * Credits.usdPerCredit, mode: mode, locale: locale),
          barFraction: MenuBarTitle.gaugeFraction(usage: copilotUsage, mode: mode),
          spentUSD: copilotSpentUSD, resetDate: resetDate, days: days, now: now, locale: locale)
      }
    guard PortkeyBudget.showsBlock(requestCount: portkeyRequestCount, budgetUSD: portkeyBudgetUSD) else {
      return [copilotRow]
    }
    guard
      let portkeyUsage = PortkeyBudget.usage(spentUSD: portkeySpentUSD, budgetUSD: portkeyBudgetUSD, resetDate: resetDate)
    else {
      return [
        copilotRow,
        row(.portkey, amountText: "\(PortkeySpend.formatted(portkeySpentUSD, locale: locale)) spent", barFraction: nil,
          spentUSD: portkeySpentUSD, resetDate: resetDate, days: days, now: now, locale: locale),
      ]
    }
    let portkeyRow = row(
      .portkey,
      amountText: budgetText(
        shownUSD: DashboardSidebar.shownAmount(portkeyUsage, mode: mode),
        budgetUSD: portkeyUsage.entitlement, mode: mode, locale: locale),
      barFraction: MenuBarTitle.gaugeFraction(usage: portkeyUsage, mode: mode),
      spentUSD: portkeySpentUSD, resetDate: resetDate, days: days, now: now, locale: locale)
    return [copilotRow, portkeyRow]
  }

  private static func row(
    _ tab: DashboardTab, amountText: String, barFraction: Double?, spentUSD: Double, resetDate: Date, days: RunwayDays,
    now: Date, locale: Locale
  ) -> ProviderRow {
    let burnUSD = Runway.averageDailyBurn(credits: spentUSD, resetDate: resetDate, now: now, days: days)
    return ProviderRow(
      tab: tab, amountText: amountText, barFraction: barFraction,
      burnAmountText: PortkeySpend.formatted(burnUSD, locale: locale), dayWord: days.dayWord())
  }

  private static func budgetText(shownUSD: Double, budgetUSD: Double, mode: GaugeMode, locale: Locale) -> String {
    let verb =
      switch mode {
      case .left: "left"
      case .spent: "spent"
      }
    return "\(PortkeySpend.formatted(shownUSD, locale: locale)) of \(PortkeySpend.formatted(budgetUSD, locale: locale)) \(verb)"
  }
}
