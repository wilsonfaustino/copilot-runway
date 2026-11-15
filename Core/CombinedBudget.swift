import Foundation

// The gauge split: how much of the gauge each provider fills, as fractions of the combined budget.
public struct GaugeParts: Equatable, Sendable {
  public let copilot: Double
  public let portkey: Double
  public var total: Double { copilot + portkey }

  public init(copilot: Double, portkey: Double) {
    self.copilot = copilot
    self.portkey = portkey
  }
}

// One USD budget made of the Copilot credits (1 credit = US$0.01) and the Portkey monthly budget.
// usage holds USD amounts, so Runway and MenuBarTitle compute the combined runway with the Copilot rules.
public struct CombinedBudget: Equatable, Sendable {
  public let usage: QuotaUsage
  private let copilotSpentUSD: Double
  private let copilotLeftUSD: Double
  private let portkeySpentUSD: Double
  private let portkeyLeftUSD: Double

  // nil without a Portkey budget above 0, or on an unlimited Copilot plan.
  public static func make(copilot: QuotaUsage, portkeySpentUSD: Double, portkeyBudgetUSD: Double?) -> CombinedBudget? {
    guard !copilot.isUnlimited, let portkeyBudgetUSD, portkeyBudgetUSD > 0 else { return nil }
    let copilotSpentUSD = copilot.creditsUsed * Credits.usdPerCredit
    let copilotLeftUSD = copilot.creditsRemaining * Credits.usdPerCredit
    let portkeyLeftUSD = portkeyBudgetUSD - portkeySpentUSD
    let budgetUSD = copilot.entitlement * Credits.usdPerCredit + portkeyBudgetUSD
    let leftUSD = copilotLeftUSD + portkeyLeftUSD
    let usage = QuotaUsage(
      creditsUsed: copilotSpentUSD + portkeySpentUSD,
      entitlement: budgetUSD,
      creditsRemaining: leftUSD,
      percentRemaining: leftUSD / budgetUSD * 100,
      isUnlimited: false,
      resetDate: copilot.resetDate
    )
    return CombinedBudget(
      usage: usage, copilotSpentUSD: copilotSpentUSD, copilotLeftUSD: copilotLeftUSD,
      portkeySpentUSD: portkeySpentUSD, portkeyLeftUSD: portkeyLeftUSD)
  }

  // The parts add up to the gauge fraction of usage. The Copilot part stops at the gauge, so overage in one
  // provider never pushes the gauge past the combined total. The Portkey part is the rest.
  public func parts(mode: GaugeMode) -> GaugeParts {
    let gauge = MenuBarTitle.gaugeFraction(usage: usage, mode: mode)
    let copilotAmount = mode == .left ? copilotLeftUSD : copilotSpentUSD
    let copilotPart = min(max(copilotAmount / usage.entitlement, 0), gauge)
    return GaugeParts(copilot: copilotPart, portkey: gauge - copilotPart)
  }

  // Left mode floors each amount at 0. Spent mode gives what each provider spent.
  public func amountsUSD(mode: GaugeMode) -> GaugeParts {
    switch mode {
    case .left: GaugeParts(copilot: max(copilotLeftUSD, 0), portkey: max(portkeyLeftUSD, 0))
    case .spent: GaugeParts(copilot: copilotSpentUSD, portkey: portkeySpentUSD)
    }
  }
}
